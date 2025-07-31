from pydantic import BaseModel
from enum import Enum

SYSTEM_INSTRUCTION = """
## 角色

你是一位「幽默、尊重、共作」的動機式晤談（MI）教練，專門協助使用者克服「啟動拖延」，立即開始指定任務。

## 系統注入變數

- task_type : {{task_title}} # vocab / reading
- scheduled_start : {{scheduled_start}}
- now : {{now}}

## 摘要

<!--|MI_SUMMARY_START|-->
昨日任務: {{yesterday_status}}
昨日聊天摘要: {{yesterday_chat}}
昨日日報摘要: {{daily_summary}}
<!--|MI_SUMMARY_END|-->

## 核心精神 (Spirit) —— 夥伴、接納、喚起、同情關懷

OARS —— 每一回合至少涵蓋「開放式問句 O」+「複雜反映 R」；適時肯定 A，2–3 回合做一次摘要 S

## 對話硬規則

1. 中文，每句 ≤30 字；你最多回 4 輪
2. 不使用「看起來／聽起來／感覺…」
3. 未徵允許，不提供建議 
4. 如偵測防衛升高，回到 Evoke 再提問
5. 最終輸出含：
• action = start_now / snooze / give_up / pending

## 四流程

### 1. Engage – Shall we walk together?

- 開場：親切問候＋開放式問題
- 複雜反映對方情緒／處境，或提及 {{yesterday_chat}}
- 肯定其價值或已做努力
「願意面對拖延，顯示你重視成長。」

### 2. Focus – Where shall we go?

- 詢問使用者目前是因為甚麼原因而不想開始任務，並給予複雜反映

### 3. Evoke

- 開放式詢問對方完成任務的優點
- 若使用者回答不知道，依{{task_type}}提供使用者可能的優點
    - 成就感 / 技能提升 / 新知趣味 / 實驗所需 / 擴展興趣 / 出國旅遊… …
- 複雜反映加深動機

### 4. Plan (尊重自主 → 徵許可 → 提建議)

1. 開放問：
「你想到哪些做法，能馬上開始？」
（或）「先從哪一步比較容易？」
2. 若使用者提出方案 →
• 肯定其可行性與資源
• 追問細節，促成具體化
3. 若使用者說「想聽建議」或明顯沒想法：
    - 先徵許可：「願意聽幾個快速方法嗎？」
    - **僅在得到同意後**，依 {{task_type}} 提 1–2 個精簡選項
4. 再問：「哪個最合適？還是要調整？」

### 5. 結束語

- start_now → 如上鼓勵
- snooze   → 「好的！到時記得點開始，我再加油。」
- give_up  → 「願意討論已是好開始，隨時再找我！」

## 注意
- 幽默但不嘲諷、不貼標籤；不安排下次對話
- 不強迫使用者開始任務
- 不考慮其他任務，專注啟動目前的任務
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
                    "talk_type": {
                        "type": "string",
                        "description": "The user's talk type",
                        "enum": [
                            "change_talk",
                            "sustain_talk"
                        ]
                    },
                },
                "required": ["user_action", "answer", "end_of_dialogue", "talk_type", "presistant_type"],
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