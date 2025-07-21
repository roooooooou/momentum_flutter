from pydantic import BaseModel
from enum import Enum

SYSTEM_INSTRUCTION = """
# 使用者背景
- 任務：{{task_title}}
- 原定開始：{{scheduled_start}}
- 現在時間：{{now}}
- 問題：面臨任務啟動困難的問題，需要幫助

# 角色
你是幽默的「任務啟動教練」，請在當下運用【動機式晤談 (MI) + 承諾裝置】來幫助使用者
提供明確且具體的建議，來幫助使用者願意現在開始執行任務。

# MI 精神
- 共情：保持高度同理、耐心傾聽，應經常重述用戶的話以確認理解，適時給予肯定
- 合作：每一句話都用問句引導
- 自主：尊重決定，不給予過多直接建議
- 喚起：讓對方自己說理由，判斷使用者拖延的心理因素

# 目標
3-4 回合內，引導使用者立刻開始任務。

# 格式規則
1. 每句 ≤30 字。
2. 使用中文

# user_action 定義
start_now / snooze / give_up / pending

# 流程規則
    # R0 - Focus
    若任務的內容無法從{{task_title}}判斷，請先釐清任務大致的內容或類型，記得考慮任務的內容來給予建議

    # R1 - Engage
    共情：反映情緒，表示理解。
    建立連結：簡短肯定。
    了解阻礙：詢問目前最卡關的點或拖延原因。

    # R2 – Evoke  
    反映情緒或摘要阻礙，同理使用者阻礙的原因。
    接著提出價值問句，讓使用者自己提出完成任務的動機/優點
    若回答 <10 字或「不知道」→ 提供三個具體選項，請其選擇。

    # R3 – Plan  
    反映使用者剛才說的動機／顧慮。
    立即接一個開放式問題，引導 change-talk：讓使用者思考可以開始任務的方法
    若使用者有提出可能的方案，則根據方案提供建議；
    若使用者沒有自己提出可能的方案，則根據 resistance_type 挑單一技巧：
    overwhelm→任務切塊；distraction→環境佈署；unclear→醜草稿；low_energy→5 分鐘規則；emotion→自我慰問 + 番茄鐘
    技巧如：5分鐘規則、番茄鐘、環境佈署、If-Then 計畫、醜草稿⋯⋯或根據狀況提供

    # R4 – Commit
    先確認使用者接受R3提出的建議，若使用者願意，才可以請使用者輸入 commit_plan：When-Where-What
    (時間｜地點｜要做的第一步)
    完整輸入後 → action=start_now 並回傳 commit_plan。

# 結束條件
    若user已經願意開始，不一定要按照流程走完，只要有commit_plan就可以結束
    start_now + commit_plan → 鼓勵：「完成後回 App 勾選任務，我在終點揮旗！」 → 結束
    snooze + commit_plan → 鼓勵：「好的！到時記得點開始，我會再為你加油。」 → 結束
    give_up → 肯定：「願意聊已是好開始，隨時再找我！」 → 結束

# 注意
- 幽默但不嘲諷、不貼標籤；不安排下次對話
- 不強迫使用者開始任務
- 在要求使用者提供Commit Plan時，請要求他完整的打出來時間、地點、任務，要考慮現在時間 {{now}}
"""

class responseFormat(BaseModel):
    answer: str
    end_of_dialogue: bool
    suggested_action: str
    commit_plan: str

class action(str, Enum):
    start_now = "start_now"
    snooze = "snooze"
    give_up_today = "give_up_today"
    pending = "pending"

def get_response_schema() -> dict:
    responseFormat = {
        'type': 'json_schema',
        'json_schema': {
            "name": "coach",
            'strict': True,
            "schema": {
                "type": "object",
                "properties": {
                    "user_action": {
                        "type": "string",
                        "description": "The action user take",
                        "enum": [
                            "start_now",
                            "snooze",
                            "pending",
                            "give_up"
                        ]
                    },
                    "presistant_type": {
                        "type": "string",
                        "description": "The type of persistant problem",
                        "enum": [
                            "overwhelm",
                            "distraction",
                            "unclear",
                            "low_energy",
                            "emotion",
                            "none"
                        ]
                    },
                    "answer": {
                        "type": "string",
                        "description": "The answer to the user's question"
                    },
                    "end_of_dialogue": {
                        "type": "boolean",
                        "description": "Whether the dialogue is over"
                    },
                    "commit_plan": {
                        "type": "string",
                        "description": "The user's commitment plan"
                    },
                },
                "required": ["user_action", "answer", "end_of_dialogue", "commit_plan", "presistant_type"],
                "additionalProperties": False
            }
        }
    }
    return responseFormat

def get_summarize_schema() -> dict:
    summarizeFormat = {
        'type': 'json_schema',
        'json_schema': {
            "name": "summarize",
            'strict': True,
            "schema": {
                "type": "object",
                "properties": {
                    "snooze_reasons": {
                        "type": "array",
                        "items": {
                            "type": "string"
                        }
                    },
                    "summary": {
                        "type": "string",
                    },
                    "coach_methods": {
                        "type": "array",
                        "items": {
                            "type": "string"
                        }
                    },
                    "result":{
                        "type": "string",
                        "description": "The action user take",
                        "enum": [
                            "start",
                            "snooze",
                            "give_up"
                        ]
                    }
                },
                "required": ["snooze_reasons", "summary", "coach_methods", "result"],
                "additionalProperties": False
            }
        }
    }
    return summarizeFormat