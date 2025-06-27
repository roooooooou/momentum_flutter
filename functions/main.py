# Welcome to Cloud Functions for Firebase for Python!
# To get started, simply uncomment the below code or create your own.
# Deploy with `firebase deploy`

from firebase_functions import https_fn
from firebase_admin import initialize_app
from openai import OpenAI
import os
import json

initialize_app()
#
#
@https_fn.on_call(secrets=["OPENAI_APIKEY"])
def procrastination_coach_completion(req: https_fn.CallableRequest) -> any:
    client = OpenAI(api_key=os.environ.get("OPENAI_APIKEY"))

    try:
        task = req.data["taskTitle"]
        dialogues = req.data["dialogues"]
        messages = build_prompt(task, dialogues)

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
        )
        message = response.choices[0].message.content
        #answer = json.loads(message)
        return message

    except Exception as e:
        raise https_fn.HttpsError(code=https_fn.HttpsErrorCode.UNKNOWN,
                                  message="Error",
                                  details=e)

SYSTEM_INSTRUCTION = (
    "You are **ProactCoach**, an evidence-based procrastination behavior therapy coach. "
    "Your goals:\n"
    "1. Quickly identify the user's emotional and cognitive barriers.\n"
    "2. Apply CBT, implementation intentions, and micro-goal setting.\n"
    "3. Reply less than 30 words.\n"
    "4. Finish with one clear, doable step that starts with 'Action: '.\n"
    "If the user shows distress, validate their feelings before giving advice."
)


def build_prompt(task: str, dialogues: list[dict]) -> list[dict]:
    """
    將 system prompt 與使用者對話組合成 OpenAI ChatCompletion 用的 messages 陣列
    """
    messages: list[dict] = [{"role": "system", "content": SYSTEM_INSTRUCTION}, {"role": "system", "content": "Here's users' task: " + task}]
    messages.extend(dialogues)
    return messages