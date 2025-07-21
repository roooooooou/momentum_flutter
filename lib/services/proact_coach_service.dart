import '../models/chat_message.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// 聊天完成结果，包含消息和token使用量
class ChatCompletionResult {
  final ChatMessage message;
  final int totalTokens;
  
  ChatCompletionResult({
    required this.message,
    required this.totalTokens,
  });
}

/// 聊天总结结果，包含总结内容、拖延原因和教练方法
class ChatSummaryResult {
  final String summary;
  final List<String> snoozeReasons;
  final List<String> coachMethods;
  
  ChatSummaryResult({
    required this.summary,
    required this.snoozeReasons,
    required this.coachMethods,
  });
}

class ProactCoachService {
  final _fn = FirebaseFunctions.instance
      .httpsCallable('procrastination_coach_completion');
  final _summarizeFn = FirebaseFunctions.instance
      .httpsCallable('summarize_chat');

  Future<ChatCompletionResult> getCompletion(
      List<ChatMessage> history, String taskTitle, DateTime startTime, int currentTurn, {String? taskDescription}) async {
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
      'taskDescription': taskDescription, // 新增描述參數
      'dialogues': mapped,
      'startTime': formattedStartTime,
      'currentTurn': currentTurn
    });
    print('LLM response: ${res.data}');
    
    // 從響應中提取end_of_dialogue字段
    final endOfDialogue = res.data['end_of_dialogue'] ?? false;
    
    // 🎯 新增：提取suggested_action字段
    final suggestedAction = res.data['user_action'] ?? 'pending';
    
    // 🎯 新增：提取commit_plan字段
    final commitPlan = res.data['commit_plan'];
    
    // 安全地提取token使用量信息
    final tokenUsageRaw = res.data['token_usage'];
    int totalTokens = 0;
    
    if (tokenUsageRaw != null) {
      // 🎯 調試：檢查原始token usage數據
      print('Token usage raw type: ${tokenUsageRaw.runtimeType}');
      print('Token usage raw content: $tokenUsageRaw');
      
      // 安全地轉換並提取total_tokens
      if (tokenUsageRaw is Map) {
        totalTokens = (tokenUsageRaw['total_tokens'] as num?)?.toInt() ?? 0;
      }
    }
    
    // 🎯 調試：檢查answer內容
    final answerContent = res.data['answer'];
    print('Raw answer content: "$answerContent"');
    print('Answer content type: ${answerContent.runtimeType}');
    print('Answer content length: ${answerContent?.toString().length ?? 0}');
    print('Suggested action: $suggestedAction');
    print('Final total tokens: $totalTokens');
    
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: answerContent?.toString() ?? '⚠️ 無法獲取回應內容',
      endOfDialogue: endOfDialogue,
      extra: {
        'suggested_action': suggestedAction,
        if (commitPlan != null && commitPlan.toString().isNotEmpty) 'commit_plan': commitPlan.toString(),
      },
    );
    
    // 🎯 調試：檢查創建的message
    print('Created message content: "${message.content}"');
    print('Created message endOfDialogue: ${message.endOfDialogue}');
    print('Created message suggested_action: ${message.extra?['suggested_action']}');
    
    return ChatCompletionResult(
      message: message,
      totalTokens: totalTokens,
    );
  }

  String _roleToString(ChatRole r) => r == ChatRole.user
      ? 'user'
      : r == ChatRole.assistant
          ? 'assistant'
          : 'system';

  /// 调用 summarize_chat 云函数获取对话总结
  Future<ChatSummaryResult> summarizeChat(List<ChatMessage> messages) async {
    // 将 ChatMessage 转换为云函数需要的格式
    final mapped = messages
        .map((m) => {'role': _roleToString(m.role), 'content': m.content})
        .toList();
    
    print('Summarizing chat with ${mapped} messages');
    
    final res = await _summarizeFn.call({'messages': mapped});
    print('Summary response: ${res.data}');
    
    return ChatSummaryResult(
      summary: res.data['summary'] ?? '',
      snoozeReasons: List<String>.from(res.data['snooze_reasons'] ?? []),
      coachMethods: List<String>.from(res.data['coach_methods'] ?? []),
    );
  }
}
