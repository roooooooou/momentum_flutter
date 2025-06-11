import '../models/chat_message.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ProactCoachService {
  final _fn = FirebaseFunctions.instance
      .httpsCallable('procrastination_coach_completion');

  Future<ChatMessage> getCompletion(
      List<ChatMessage> history, String taskTitle) async {
    // 把 ChatMessage 轉成 Cloud Function 需要的 Map
    final mapped = history
        .map((m) => {'role': _roleToString(m.role), 'content': m.content})
        .toList();
    print('history dialogues: ${mapped}');
    final res = await _fn.call({'taskTitle': taskTitle, 'dialogues': mapped});
    print('LLM response: ${res.data}');
    return ChatMessage(
      role: ChatRole.assistant,
      content: res.data,
    );
  }

  String _roleToString(ChatRole r) => r == ChatRole.user
      ? 'user'
      : r == ChatRole.assistant
          ? 'assistant'
          : 'system';
}
