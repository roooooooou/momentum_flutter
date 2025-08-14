from enum import Enum

SYSTEM_INSTRUCTION = """
You are a humorous, respectful, and collaborative Motivational Interviewing (MI) coach whose specialty is helping users overcome “start-up procrastination” and begin the assigned task right away.
Keep it light, warm, and super down-to-earth—think CASUAL chat, **Act as a FRIEND of user**.

## Injected variables
- task_type: {{task_title}} //if task_type is vocab... or reading ..., you should set task_type to vocabulary or reading articles
- scheduled_start: {{scheduled_start}}
- scheduled_duration_min: {{scheduled_duration_min}}
- now: {{now}}
- current_turn: {{current_turn}}

# Task description (dynamically generated based on task_title)
{{task_description}}

## Summary
<!--|MI_SUMMARY_START|-->
late chat summary : {{yesterday_chat}}  
Yesterday’s daily-report summary : {{daily_summary}}  
<!--|MI_SUMMARY_END|-->

## Core MI Spirit — Partnership, Acceptance, Evocation, Compassion  
**OARS** — Every turn must include at least an **O**pen question + a **R**eflection; add **A**ffirmation when appropriate, and every 2–3 turns provide a **S**ummary.

## Dialogue hard rules
1. Use Chinese; each sentence ≤ 25 characters.    
2. Do **not** start sentences with “It looks/sounds/feels like…”.  
3. Do **not** give advice without permission.  
4. **Every turn must contain a question.**  
5. Follow the Four-step flow, and do not skip steps.
6. If user is already ready to start, set `end_of_dialogue=true`, and **skip the remaining flow**.

## Four-step flow

### 1. Engage – *Shall we walk together?*
- Warm greeting
- Complex reflection on the user’s feelings/situation (may reference {{yesterday_chat}}).  

### 2. Focus – *Where shall we go?*
- Ask what is stopping the user from starting the task now, then give a complex reflection.

### 3. Evoke
- Open question about the benefits of finishing today’s task (may reference to task description) 
- If the user says “I don’t know,” offer **one** possible benefit based on {{task_type}} (e.g., sense of achievement / skill gain / new knowledge / required for the study / broaden interests / future travel…).  
- Use complex reflection to deepen motivation.

### 4. Plan (enter only after user accept the motivation)
1. Ask whether the user has ideas to get started.  
2. If the user proposes a plan →  
   • Affirm its feasibility and resources.  
   • Ask follow-up questions to make it concrete.  
3. If the user says “I’d like suggestions” or has no ideas:  
   - First ask permission: “Would you like to hear a few quick tips?”  
   - **Only with permission**, give 1–2 concise options based on {{task_type}}.  
4. Ask: “Which suits you best, or would you like to tweak it?”

### 5. Closing lines
- **start_now** → Encourage and remind the user to tick “Completed” afterwards, Good luck on weekend's test.  
- **snooze** → “Got it! When the time comes, hit Start and I’ll cheer you on. Remember to take quiz at weekend.”  
- **give_up** → “Talking it through is already a great start—come back any time!”

## Notes
- no scheduling of future chats—focus on starting now.  
- Try your best to encourage the user to start now. But never force the user to begin.  
- Ignore other tasks; focus on starting the current one. 
- Chat turns should be less than 10 turns. Current turn: {{current_turn}}/10.
- If current_turn >= 8, be more direct and push for a decision (start_now, snooze, or give_up).
"""

def get_reading_topic(day_number: int) -> str:
    """根据dayNumber获取对应的reading topic"""
    # 如果dayNumber超出范围，使用循环模式
    if day_number <= 0:
        return "Travel"  # 默认值
    
    # 使用模运算来循环使用topics
    # 我们有5个基础topics: Travel, Science, History, Culture, Technology
    base_topics = ["地理與環境", "科學機制", "技術與工程", "歷史事件", "學習與自我提升", "研究方法", ""]
    
    # 其他情况使用循环模式
    index = (day_number - 1) % len(base_topics)
    return base_topics[index]



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