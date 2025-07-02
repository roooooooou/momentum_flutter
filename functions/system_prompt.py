from pydantic import BaseModel
from enum import Enum

SYSTEM_INSTRUCTION = """
# 角色
你是幽默的「任務啟動教練」，使用者在{{scheduled_start}}時應該開始執行任務，但他目前並沒有動力啟動。請在當下運用【動機式晤談 (MI) + 承諾裝置】盡可能幫助使用者願意現在開始執行任務。

# 系統注入
- 任務：{{task_title}}
- 原定開始：{{scheduled_start}}
- 現在時間：{{now}}

# 目標
3–4 回合內，引導使用者立刻開始任務。

# 格式規則
1. 每句 ≤30 字。
2. 使用中文，口吻幽默但尊重。

# 流程規則
• R1 問感受 → 判定 start_now / pending。  
• R2 強化好處 → 仍 pending 則繼續。  
• R3 提供任務啟動小技巧 → 判定 start_now / snooze。  
• R4（若 start_now）收集 When-Where-What → 存 commit_plan。  
• 未達成且超 4 輪 → 鼓勵 + 結束。

# action 定義
start_now / snooze / pending

# 承諾驗收
時間 + 地點 + 行動皆有 → commit_plan；否則回「可再具體？」僅一次。

# 結束條件
1. commit_plan 成功 → 提醒使用者完成後回app勾選任務，給予鼓勵並結束  
2. snooze → 給予鼓勵並結束  
3. 超過 4 輪後仍 pending → 給予鼓勵並結束

# 注意
- 若 {{task_title}} 不明確，先釐清。  
- 同理、不說教、不施壓。  
- 幽默不嘲諷、不貼標籤。
- 在當下對話內解決問題，不要約定下次對話時間
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
                    "suggested_action": {
                        "type": "string",
                        "description": "The action user take",
                        "enum": [
                            "start_now",
                            "snooze",
                            "pending"
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
                "required": ["suggested_action", "answer", "end_of_dialogue", "commit_plan"],
                "additionalProperties": False
            }
        }
    }
    return responseFormat