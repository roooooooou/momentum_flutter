import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../services/proact_coach_service.dart';

class ChatProvider extends ChangeNotifier {
  final _coach = ProactCoachService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  final String taskTitle;
  final DateTime startTime;
  int _currentTurn = 0;
  bool _hasStarted = false; // 標記是否已經開始對話

  ChatProvider({required this.taskTitle, required this.startTime});

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  int get currentTurn => _currentTurn;
  
  /// 檢查對話是否已結束
  bool get isDialogueEnded {
    if (_messages.isEmpty) return false;
    // 檢查最後一條助手消息是否標記了對話結束
    final lastAssistantMessage = _messages.lastWhere(
      (msg) => msg.role == ChatRole.assistant,
      orElse: () => ChatMessage(role: ChatRole.assistant, content: ''),
    );
    return lastAssistantMessage.endOfDialogue;
  }

  /// 使用者送出文字
  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty || isDialogueEnded) return; // 對話結束時不允許發送消息
    _messages.add(ChatMessage(
        id: const Uuid().v4(), role: ChatRole.user, content: text.trim()));
    _currentTurn++; // 增加turn計數
    notifyListeners();
    await _fetchAssistantReply();
  }

  Future<void> _fetchAssistantReply() async {
    _isLoading = true;
    notifyListeners();

    try {
      final reply = await _coach.getCompletion(_messages, taskTitle, startTime, _currentTurn);
      _messages.add(reply);
    } catch (e) {
      _messages
          .add(ChatMessage(role: ChatRole.assistant, content: '⚠️ 發生錯誤，請稍後再試'));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// AI主動開始對話
  Future<void> startConversation() async {
    if (_hasStarted) return; // 避免重複開始
    _hasStarted = true;
    
    // AI主動問第一個問題（根據system prompt的Turn 0）
    await _fetchAssistantReply();
  }

  void reset() {
    _messages.clear();
    _currentTurn = 0; // 重置turn計數
    _hasStarted = false; // 重置開始狀態
    notifyListeners();
  }
}
