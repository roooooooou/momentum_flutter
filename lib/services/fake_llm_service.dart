import 'dart:async';
import '../models/chat_message.dart';
import 'proact_coach_service.dart'; // 繼承好沿用型別

/// 一個「什麼都不呼叫外網」的假服務
class FakeLLMService extends ProactCoachService {
  FakeLLMService() : super();

  @override
  Future<ChatMessage> getCompletion(
      List<ChatMessage> history, String task) async {
    // 模擬網路延遲；建議 500~1500 ms 之間觀察 loading indicator
    await Future.delayed(const Duration(milliseconds: 800));

    // 取最後一句，回傳簡單 echo
    final lastUserMsg =
        history.lastWhere((m) => m.role == ChatRole.user).content;

    return ChatMessage(
      role: ChatRole.assistant,
      content: '🧪 假回覆：你剛剛說「$lastUserMsg」對吧?',
    );
  }
}
