# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import https_fn
from firebase_admin import initialize_app
from openai import OpenAI
import os
import json
from datetime import datetime
import pytz
import system_prompt

initialize_app()
#
#
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