# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import https_fn, scheduler_fn
from firebase_admin import initialize_app, firestore, credentials
from openai import OpenAI
import os
import json
from datetime import datetime, timedelta
import pytz
import system_prompt

# 使用默認憑證初始化，確保有完整的 admin 權限
initialize_app()

def get_firestore_client():
    """延迟初始化Firestore客户端，避免部署时超时"""
    return firestore.client()

# 🧪 测试定时器函数（每分钟执行一次）
@scheduler_fn.on_schedule(schedule="*/5 * * * *", timezone="Asia/Taipei")  # 每5分钟执行一次
def test_scheduler(event: scheduler_fn.ScheduledEvent) -> None:
    """
    测试定时器函数：每5分钟执行一次，用于验证Cloud Scheduler是否正常工作
    """
    try:
        taiwan_tz = pytz.timezone('Asia/Taipei')
        now = datetime.now(taiwan_tz)
        
        print(f"🎯 测试定时器执行成功！时间: {now.strftime('%Y-%m-%d %H:%M:%S')} (台湾时间)")
        
        # 可选：写入Firestore记录执行历史
        db = get_firestore_client()
        test_ref = db.collection('test_scheduler').document()
        test_ref.set({
            'executed_at': now,
            'message': '定时器测试执行成功',
            'timezone': 'Asia/Taipei'
        })
        
    except Exception as e:
        print(f"❌ 测试定时器执行失败: {e}")

@https_fn.on_call(secrets=["OPENAI_APIKEY"])
def procrastination_coach_completion(req: https_fn.CallableRequest) -> any:
    client = OpenAI(api_key=os.environ.get("OPENAI_APIKEY"))

    try:
        task = req.data["taskTitle"]
        dialogues = req.data["dialogues"]
        start_time = req.data["startTime"]
        current_turn = req.data.get("currentTurn", 0)

        messages = build_prompt(task, dialogues, start_time, current_turn)
        response = client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=messages,
            response_format=system_prompt.get_response_schema()
        )
        message = response.choices[0].message.content
        answer = json.loads(message)
        
        # 🎯 實驗數據收集：添加token使用量信息
        if hasattr(response, 'usage') and response.usage:
            answer['token_usage'] = {
                'prompt_tokens': response.usage.prompt_tokens,
                'completion_tokens': response.usage.completion_tokens,
                'total_tokens': response.usage.total_tokens
            }
        
        return answer

    except Exception as e:
        raise https_fn.HttpsError(code=https_fn.HttpsErrorCode.UNKNOWN,
                                  message="Error",
                                  details=e)


def build_prompt(task: str, dialogues: list[dict], start_time: str, current_turn: int) -> list[dict]:
    """
    將 system prompt 與使用者對話組合成 OpenAI ChatCompletion 用的 messages 陣列
    """
    # 將任務資訊帶入 SYSTEM_INSTRUCTION 模板
    # 使用台灣時區
    taiwan_tz = pytz.timezone('Asia/Taipei')
    now_taiwan = datetime.now(taiwan_tz).strftime('%Y-%m-%d %H:%M')
    system_content = system_prompt.SYSTEM_INSTRUCTION.replace("{{task_title}}", task).replace("{{scheduled_start}}", start_time).replace("{{now}}", now_taiwan)
    system_content += f"\n\n🔄 對話狀態：目前為第 {current_turn} 輪對話"
    
    # 建立訊息陣列：僅保留一個 system role，後續直接接上 dialogues
    messages: list[dict] = [{"role": "system", "content": system_content}]
    messages.extend(dialogues)
    return messages

@https_fn.on_call(secrets=["OPENAI_APIKEY"])
def summarize_chat(req: https_fn.CallableRequest) -> any:
    client = OpenAI(api_key=os.environ.get("OPENAI_APIKEY"))

    try:
        messages = req.data["messages"]  # list of dict: {role, content}
        # 將對話格式化成文字
        dialogue_text = ""
        for m in messages:
            role = m.get("role", "")
            content = m.get("content", "")
            dialogue_text += f"{role}: {content}\n"

        prompt = f"""
            請幫我從以下對話中：
            1. 萃取所有使用者提到的「延後/拖延」原因（以 array 回傳，若無請回傳空陣列）
            2. 萃取AI教練提出的具體建議或方法（以 array 回傳，若無請回傳空陣列）
            3. 用一段話摘要這次對話的重點

            請用以下 JSON 格式回傳：
            {{
            "snooze_reasons": [ ... ],
            "coach_methods": [ ... ],
            "summary": "..."
            }}

            對話內容如下：
            {dialogue_text}
            """

        response = client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=[
                {"role": "system", "content": prompt}
            ],
            response_format = system_prompt.get_summarize_schema()
        )
        # 解析回傳
        message = response.choices[0].message.content
        result = json.loads(message)
        return result

    except Exception as e:
        raise https_fn.HttpsError(
            code=https_fn.HttpsErrorCode.UNKNOWN,
            message="summarize_chat error",
            details=str(e)
        )


@scheduler_fn.on_schedule(schedule="*/5 * * * *", timezone="Asia/Taipei", timeout_sec=540)  # 每天凌晨3:30執行，增加超时时间到9分钟
def daily_metrics_aggregation(event: scheduler_fn.ScheduledEvent) -> None:
    """
    每日數據聚合函數：計算前一天的所有指標並存儲到 daily_metrics collection
    """
    try:
        print("🚀 每日數據聚合開始執行...")
        
        # 計算前一天的日期 (台灣時區)
        taiwan_tz = pytz.timezone('Asia/Taipei')
        yesterday = datetime.now(taiwan_tz) - timedelta(days=1)
        date_str = yesterday.strftime('%Y%m%d')
        
        print(f"📅 處理日期: {date_str}")
        
        # 獲取所有使用者 - 添加延遲等待初始化
        print("🔄 初始化 Firestore 客戶端...")
        import time
        time.sleep(2)  # 等待2秒確保初始化完成
        
        db = get_firestore_client()
        users_ref = db.collection('users')
        
        print("🔍 嘗試獲取用戶列表...")
        
        # 嘗試多種方法獲取用戶
        try:
            # 方法1：直接get()
            users_docs = users_ref.get()
            users_list = list(users_docs)
            print(f"📊 方法1 - 找到 {len(users_list)} 個用戶")
            
            # 方法2：使用stream()
            try:
                users_stream = list(users_ref.stream())
                print(f"📊 方法2 - stream() 找到 {len(users_stream)} 個用戶")
            except Exception as stream_error:
                print(f"❌ stream() 方法失敗: {stream_error}")
            
            # 方法3：嘗試查詢所有collection
            try:
                all_collections = db.collections()
                collection_names = [col.id for col in all_collections]
                print(f"🗂️ 數據庫中的所有collections: {collection_names}")
            except Exception as col_error:
                print(f"❌ 獲取collections失敗: {col_error}")
            
            # 方法4：嘗試使用limit查詢
            try:
                limited_query = users_ref.limit(10).get()
                limited_list = list(limited_query)
                print(f"📊 方法4 - limit(10) 找到 {len(limited_list)} 個用戶")
            except Exception as limit_error:
                print(f"❌ limit查詢失敗: {limit_error}")
            
            if len(users_list) == 0:
                print("⚠️  警告：沒有找到任何用戶")
                # 記錄詳細信息
                print(f"🔍 調試信息 - Collection ID: {users_ref.id}")
                print(f"🔍 調試信息 - DB 實例: {type(db)}")
                print(f"🔍 調試信息 - DB project: {db.project}")
                
                # 嘗試直接檢查是否有已知用戶ID
                known_uid = "A1HISgLipRW3EpxFpdWjUD6Fko83"  # 從之前的手動測試中看到的
                try:
                    test_user_doc = db.collection('users').document(known_uid).get()
                    print(f"🔍 已知用戶 {known_uid} 存在: {test_user_doc.exists}")
                    if test_user_doc.exists:
                        user_data = test_user_doc.to_dict()
                        print(f"🔍 用戶數據: {user_data}")
                        print(f"🔍 用戶數據長度: {len(user_data) if user_data else 0}")
                    else:
                        print(f"🔍 用戶文檔不存在或為空")
                        
                    # 嘗試檢查用戶的子集合
                    try:
                        events_ref = db.collection('users').document(known_uid).collection('events')
                        events_query = events_ref.limit(1).get()
                        events_list = list(events_query)
                        print(f"🔍 用戶 {known_uid} 的事件數量: {len(events_list)}")
                    except Exception as events_error:
                        print(f"❌ 檢查用戶事件失敗: {events_error}")
                        
                except Exception as test_error:
                    print(f"❌ 檢查已知用戶失敗: {test_error}")
                    print(f"🔍 錯誤詳情: {type(test_error).__name__}: {test_error}")
                
                # 嘗試使用不同的方式初始化 Firestore
                try:
                    print("🔄 嘗試重新初始化 Firestore...")
                    import firebase_admin
                    from firebase_admin import credentials
                    
                    # 檢查當前 app 狀態
                    try:
                        current_app = firebase_admin.get_app()
                        print(f"🔍 當前 Firebase App: {current_app.name}")
                        print(f"🔍 當前 Project ID: {current_app.project_id}")
                    except ValueError:
                        print("❌ 沒有找到活躍的 Firebase App")
                        
                except Exception as init_error:
                    print(f"❌ Firestore 重新初始化失敗: {init_error}")
                
        except Exception as users_error:
            print(f"❌ 獲取用戶列表時發生錯誤: {users_error}")
            print(f"🔍 錯誤類型: {type(users_error).__name__}")
            print(f"🔍 錯誤詳情: {str(users_error)}")
            raise
        
        processed_count = 0
        error_count = 0
        
        for user_doc in users_list:
            uid = user_doc.id
            try:
                print(f"🔄 處理用戶: {uid}")
                metrics = calculate_daily_metrics(uid=uid, target_date=yesterday, db=db)
                
                # 儲存到 daily_metrics
                metrics_ref = db.collection('users').document(uid).collection('daily_metrics').document(date_str)
                metrics_ref.set(metrics)
                
                print(f"✅ 用戶 {uid} 的 {date_str} 日報數據已生成")
                processed_count += 1
                
            except Exception as user_error:
                print(f"❌ 處理用戶 {uid} 時發生錯誤: {user_error}")
                error_count += 1
                continue
                
        print(f"🎯 每日數據聚合完成: {date_str}, 成功: {processed_count}, 失敗: {error_count}")
        
        # 記錄執行結果到Firestore
        execution_log_ref = db.collection('daily_metrics_execution_log').document(date_str)
        execution_log_ref.set({
            'date': date_str,
            'executed_at': datetime.now(taiwan_tz),
            'processed_count': processed_count,
            'error_count': error_count,
            'status': 'completed',
            'timezone': 'Asia/Taipei'
        })
        
    except Exception as e:
        print(f"❌ 每日數據聚合失敗: {e}")
        
        # 記錄失敗到Firestore
        try:
            taiwan_tz = pytz.timezone('Asia/Taipei')
            yesterday = datetime.now(taiwan_tz) - timedelta(days=1)
            date_str = yesterday.strftime('%Y%m%d')
            
            db = get_firestore_client()
            execution_log_ref = db.collection('daily_metrics_execution_log').document(date_str)
            execution_log_ref.set({
                'date': date_str,
                'executed_at': datetime.now(taiwan_tz),
                'error': str(e),
                'status': 'failed',
                'timezone': 'Asia/Taipei'
            })
        except:
            pass  # 如果记录失败也失败，不要抛出异常
        
        raise


@https_fn.on_call()
def test_users_access(req: https_fn.CallableRequest) -> any:
    """
    測試用戶訪問權限的函數
    """
    try:
        db = get_firestore_client()
        users_ref = db.collection('users')
        
        print("🧪 測試函數：嘗試獲取用戶列表...")
        
        # 嘗試多種方法
        results = {}
        
        # 方法1：get()
        try:
            users_docs = users_ref.get()
            users_list = list(users_docs)
            results['get_method'] = {
                'success': True,
                'count': len(users_list),
                'user_ids': [doc.id for doc in users_list]
            }
        except Exception as e:
            results['get_method'] = {
                'success': False,
                'error': str(e)
            }
        
        # 方法2：直接檢查已知用戶
        known_uid = "A1HISgLipRW3EpxFpdWjUD6Fko83"
        try:
            test_user_doc = db.collection('users').document(known_uid).get()
            results['known_user_check'] = {
                'uid': known_uid,
                'exists': test_user_doc.exists,
                'data': test_user_doc.to_dict() if test_user_doc.exists else None
            }
        except Exception as e:
            results['known_user_check'] = {
                'uid': known_uid,
                'error': str(e)
            }
        
        # 方法3：列出所有collections
        try:
            all_collections = list(db.collections())
            results['collections'] = [col.id for col in all_collections]
        except Exception as e:
            results['collections'] = {'error': str(e)}
        
        return {
            'success': True,
            'test_results': results,
            'db_info': {
                'project': db.project,
                'type': str(type(db))
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

@https_fn.on_call()
def manual_daily_metrics(req: https_fn.CallableRequest) -> any:
    """
    手動觸發每日數據聚合（用於測試）
    參數: 
    - date: 可選，格式 "YYYY-MM-DD"，默認為昨天
    - uid: 可選，指定用戶ID，默認為所有用戶
    """
    try:
        taiwan_tz = pytz.timezone('Asia/Taipei')
        
        # 解析日期參數
        date_param = req.data.get('date')
        if date_param:
            target_date = datetime.strptime(date_param, '%Y-%m-%d').replace(tzinfo=taiwan_tz)
        else:
            target_date = datetime.now(taiwan_tz) - timedelta(days=1)
        
        date_str = target_date.strftime('%Y%m%d')
        
        # 解析用戶參數
        target_uid = req.data.get('uid')
        
        if target_uid:
            # 處理單個用戶
            db = get_firestore_client()
            metrics = calculate_daily_metrics(uid=target_uid, target_date=target_date, db=db)
            metrics_ref = db.collection('users').document(target_uid).collection('daily_metrics').document(date_str)
            metrics_ref.set(metrics)
            
            return {
                'success': True,
                'message': f'用戶 {target_uid} 的 {date_str} 數據已生成',
                'metrics': metrics
            }
        else:
            # 處理所有用戶
            db = get_firestore_client()
            users_ref = db.collection('users')
            
            print("🔍 手動測試：嘗試獲取用戶列表...")
            users_docs = users_ref.get()
            users = list(users_docs)
            print(f"📊 手動測試：找到 {len(users)} 個用戶")
            results = []
            
            for user_doc in users:
                uid = user_doc.id
                try:
                    metrics = calculate_daily_metrics(uid=uid, target_date=target_date, db=db)
                    metrics_ref = db.collection('users').document(uid).collection('daily_metrics').document(date_str)
                    metrics_ref.set(metrics)
                    
                    results.append({
                        'uid': uid,
                        'status': 'success',
                        'metrics': metrics
                    })
                    
                except Exception as user_error:
                    results.append({
                        'uid': uid,
                        'status': 'error',
                        'error': str(user_error)
                    })
            
            return {
                'success': True,
                'message': f'所有用戶的 {date_str} 數據處理完成',
                'results': results
            }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }


def calculate_daily_metrics(uid: str, target_date: datetime, db) -> dict:
    """
    計算指定用戶在指定日期的所有指標
    """
    # 設定時間範圍（台灣時區的一整天）
    taiwan_tz = pytz.timezone('Asia/Taipei')
    start_of_day = target_date.replace(hour=0, minute=0, second=0, microsecond=0)
    end_of_day = start_of_day + timedelta(days=1)
    
    # 轉換為UTC進行Firestore查詢
    start_utc = start_of_day.astimezone(pytz.UTC)
    end_utc = end_of_day.astimezone(pytz.UTC)
    
    # === Event相關指標 ===
    events_ref = db.collection('users').document(uid).collection('events')
    events_query = events_ref.where('scheduledStartTime', '>=', start_utc).where('scheduledStartTime', '<', end_utc)
    events = list(events_query.stream())
    
    event_total_count = len(events)
    event_complete_count = 0
    event_overdue_count = 0
    event_not_finish_count = 0
    event_commit_plan_count = 0
    
    for event_doc in events:
        event_data = event_doc.to_dict()
        is_done = event_data.get('isDone', False)
        status = event_data.get('status')
        scheduled_start = event_data.get('scheduledStartTime')
        
        if is_done:
            event_complete_count += 1
        else:
            event_not_finish_count += 1
            
        # 檢查是否過期 (過了排程時間但未完成)
        if scheduled_start and scheduled_start.replace(tzinfo=pytz.UTC) < end_utc and not is_done:
            event_overdue_count += 1
            
        # 檢查是否有commit plan（從chats sub-collection中查詢）
        chats_ref = events_ref.document(event_doc.id).collection('chats')
        chats = list(chats_ref.stream())
        for chat_doc in chats:
            chat_data = chat_doc.to_dict()
            if chat_data.get('commit_plan', False):
                event_commit_plan_count += 1
                break  # 一個事件只計算一次
    
    # === 通知相關指標 ===
    notif_total_count = 0
    notif_open_count = 0 
    notif_dismiss_count = 0
    
    for event_doc in events:
        # 獲取所有通知記錄（包含 -1st 和 -2nd）
        notifications_ref = events_ref.document(event_doc.id).collection('notifications')
        notifications = list(notifications_ref.stream())
        
        for notif_doc in notifications:
            notif_data = notif_doc.to_dict()
            notif_total_count += 1
            
            # 檢查是否被點開
            if notif_data.get('opened_time'):
                notif_open_count += 1
            else:
                notif_dismiss_count += 1
    
    # === 應用使用相關指標 ===
    app_sessions_ref = db.collection('users').document(uid).collection('app_sessions')
    date_string = target_date.strftime('%Y%m%d')
    sessions_query = app_sessions_ref.where('date', '==', date_string)
    sessions = list(sessions_query.stream())
    
    app_open_count = len(sessions)
    app_open_by_notif_count = 0
    total_duration = 0
    valid_sessions = 0
    
    for session_doc in sessions:
        session_data = session_doc.to_dict()
        
        if session_data.get('opened_by_notification', False):
            app_open_by_notif_count += 1
            
        duration = session_data.get('duration_seconds')
        if duration and duration > 0:
            total_duration += duration
            valid_sessions += 1
    
    app_average_open_time = total_duration // valid_sessions if valid_sessions > 0 else 0
    
    # === 聊天相關指標 ===
    chat_total_count = 0
    chat_leave_count = 0
    chat_start_count = 0
    chat_snooze_count = 0
    
    for event_doc in events:
        chats_ref = events_ref.document(event_doc.id).collection('chats')
        chats = list(chats_ref.stream())
        
        for chat_doc in chats:
            chat_data = chat_doc.to_dict()
            chat_total_count += 1
            
            result = chat_data.get('result')
            if result == 0:  # start
                chat_start_count += 1
            elif result == 1:  # snooze
                chat_snooze_count += 1
            elif result == 2:  # leave
                chat_leave_count += 1
    
    # 返回所有指標
    return {
        # Event相關
        'event_total_count': event_total_count,
        'event_overdue_count': event_overdue_count,
        'event_complete_count': event_complete_count,
        'event_not_finish_count': event_not_finish_count,
        'event_commit_plan_count': event_commit_plan_count,
        
        # 通知相關
        'notif_total_count': notif_total_count,
        'notif_open_count': notif_open_count,
        'notif_dismiss_count': notif_dismiss_count,
        
        # 應用使用相關
        'app_open_count': app_open_count,
        'app_average_open_time': app_average_open_time,
        'app_open_by_notif_count': app_open_by_notif_count,
        
        # 聊天相關
        'chat_total_count': chat_total_count,
        'chat_leave_count': chat_leave_count,
        'chat_start_count': chat_start_count,
        'chat_snooze_count': chat_snooze_count,
        
        # 元數據
        'date': date_string,
        'created_at': datetime.now(taiwan_tz),
        'timezone': 'Asia/Taipei'
    }