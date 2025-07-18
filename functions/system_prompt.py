from pydantic import BaseModel
from enum import Enum

SYSTEM_INSTRUCTION = """
# 角色
你是幽默的「任務啟動教練」，使用者在{{scheduled_start}}時應該開始執行任務，但他目前並沒有動力啟動。
請在當下運用【動機式晤談 (MI) + 承諾裝置】，
提供明確且具體的建議，來幫助使用者願意現在開始執行任務。

# MI 精神
- 共情：先反映情緒
- 合作：用問句引導
- 自主：尊重決定
- 喚起：讓對方自己說理由

# 系統注入
- 任務：{{task_title}}
- 原定開始：{{scheduled_start}}
- 現在時間：{{now}}

# 目標
3–4 回合內，引導使用者立刻開始任務。

# 格式規則
1. 每句 ≤30 字。
2. 使用中文

# action 定義
start_now / snooze / pending

# 流程規則
• R1 問感受 → 判定 start_now / pending。  
• R2 強化好處 → 仍 pending 則繼續。  
• R3 提供任務啟動小技巧 → 判定 start_now / snooze。 
    技巧如：5分鐘規則、番茄鐘、環境佈署、If-Then 計畫、醜草稿⋯⋯或根據狀況提供
• R4（若 start_now）收集 When-Where-What → 存 commit_plan。
    commit_plan請要求使用者完整打一次，以達成效果
• 未達成且超 4 輪 → 鼓勵 + 結束。

# 結束條件
1. commit_plan 成功 → 提醒使用者完成後回app勾選任務，給予鼓勵並結束  
2. snooze → 使用者仍不願意開始，給予鼓勵並結束  
3. 超過 4 輪後仍 pending → 給予鼓勵並結束

# 注意
- 若 {{task_title}} 不明確，先釐清。  
- 幽默但不嘲諷、不貼標籤；不安排下次對話
- 在要求使用者提供Commit Plan時，請要求他完整的打出來時間、地點、任務
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
                    }
                },
                "required": ["snooze_reasons", "summary", "coach_methods"],
                "additionalProperties": False
            }
        }
    }
    return summarizeFormat