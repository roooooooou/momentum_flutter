import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../services/proact_coach_service.dart';
import '../utils/logger.dart';

class ChatProvider extends ChangeNotifier {
  final _coach = ProactCoachService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  final String taskTitle;

  ChatProvider({required this.taskTitle});

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  /// 使用者送出文字
  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messages.add(ChatMessage(
        id: const Uuid().v4(), role: ChatRole.user, content: text.trim()));
    notifyListeners();
    await _fetchAssistantReply();
  }

  Future<void> _fetchAssistantReply() async {
    _isLoading = true;
    notifyListeners();

    try {
      final reply = await _coach.getCompletion(_messages, taskTitle);
      _messages.add(reply);
    } catch (e, st) {
      Logger.e('LLM failed', e, st);
      _messages
          .add(ChatMessage(role: ChatRole.assistant, content: '⚠️ 發生錯誤，請稍後再試'));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _messages.clear();
    notifyListeners();
  }
}
