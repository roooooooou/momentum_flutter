import '../models/chat_message.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ProactCoachService {
  final _fn = FirebaseFunctions.instance
      .httpsCallable('procrastination_coach_completion');

  Future<ChatMessage> getCompletion(
      List<ChatMessage> history, String taskTitle, DateTime startTime, int currentTurn) async {
    // 把 ChatMessage 轉成 Cloud Function 需要的 Map
    final mapped = history
        .map((m) => {'role': _roleToString(m.role), 'content': m.content})
        .toList();
    
    // 格式化開始時間為台灣時區
    final taiwanTime = startTime.toLocal();
    final formattedStartTime = '${taiwanTime.year}-${taiwanTime.month.toString().padLeft(2, '0')}-${taiwanTime.day.toString().padLeft(2, '0')} ${taiwanTime.hour.toString().padLeft(2, '0')}:${taiwanTime.minute.toString().padLeft(2, '0')}';
    
    print('history dialogues: ${mapped}');
    print('current turn: ${currentTurn}');
    final res = await _fn.call({
      'taskTitle': taskTitle, 
      'dialogues': mapped,
      'startTime': formattedStartTime,
      'currentTurn': currentTurn
    });
    print('LLM response: ${res.data}');
    
    // 從響應中提取end_of_dialogue字段
    final endOfDialogue = res.data['end_of_dialogue'] ?? false;
    
    return ChatMessage(
      role: ChatRole.assistant,
      content: res.data['answer'],
      endOfDialogue: endOfDialogue,
    );
  }

  String _roleToString(ChatRole r) => r == ChatRole.user
      ? 'user'
      : r == ChatRole.assistant
          ? 'assistant'
          : 'system';
}
