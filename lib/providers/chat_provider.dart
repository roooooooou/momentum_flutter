import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/proact_coach_service.dart';

class ChatProvider extends ChangeNotifier {
  final _coach = ProactCoachService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  final String taskTitle;
  final DateTime startTime;
  int _currentTurn = 0;
  bool _hasStarted = false; // 標記是否已經開始對話
  
  // 實驗數據收集相關
  final String uid;
  final String eventId;
  final String chatId;
  final List<int> _latencies = []; // 記錄每次API調用的延遲
  bool _hasRecordedChatStart = false; // 避免重複記錄聊天開始
  int _totalTokens = 0; // 累積的token使用量

  ChatProvider({
    required this.taskTitle, 
    required this.startTime,
    required this.uid,
    required this.eventId,
    required this.chatId,
  });

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

    // 記錄API調用開始時間
    final startTime = DateTime.now();

    try {
      final result = await _coach.getCompletion(_messages, taskTitle, this.startTime, _currentTurn);
      _messages.add(result.message);
      
      
      // 記錄API調用延遲
      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMilliseconds;
      _latencies.add(latencyMs);
      
      // 累積token使用量
      _totalTokens += result.totalTokens;
      
      // 🎯 調試：輸出token統計信息
      debugPrint('本輪token: ${result.totalTokens}, 累積token: $_totalTokens');
    } catch (e) {
      debugPrint('_fetchAssistantReply錯誤: $e');
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
    
    // 🎯 實驗數據收集：記錄聊天會話開始
    if (!_hasRecordedChatStart) {
      try {
        await ExperimentEventHelper.recordChatStart(
          uid: uid,
          eventId: eventId,
          chatId: chatId,
        );
        _hasRecordedChatStart = true;
      } catch (e) {
        // 實驗數據收集失敗不影響用戶體驗
        debugPrint('記錄聊天開始失敗: $e');
      }
    }
    
    // AI主動問第一個問題（根據system prompt的Turn 0）
    await _fetchAssistantReply();
  }

  /// 結束聊天會話並記錄實驗數據
  Future<void> endChatSession(ChatResult result, {bool commitPlan = false}) async {
    if (!_hasRecordedChatStart) return; // 如果沒有記錄開始，就不記錄結束
    
    try {
      // 記錄聊天結束
      await ExperimentEventHelper.recordChatEnd(
        uid: uid,
        eventId: eventId,
        chatId: chatId,
        result: result.value,
        commitPlan: commitPlan,
      );
      
      // 更新統計數據
      await _updateChatStatistics();
      
      // 🎯 新增：生成并存储聊天总结
      await _generateAndSaveSummary();
    } catch (e) {
      // 實驗數據收集失敗不影響用戶體驗
      debugPrint('記錄聊天結束失敗: $e');
    }
  }
  
  /// 更新聊天統計數據
  Future<void> _updateChatStatistics() async {
    // 🎯 即使沒有延遲數據也要更新基本統計信息
    int avgLatency = 0;
    if (_latencies.isNotEmpty) {
      avgLatency = _latencies.reduce((a, b) => a + b) ~/ _latencies.length;
    }
    
    // 🎯 調試：輸出統計信息
    debugPrint('準備更新聊天統計: totalTurns=$_currentTurn, totalTokens=$_totalTokens, avgLatencyMs=$avgLatency');
    debugPrint('延遲數據數量: ${_latencies.length}, 延遲列表: $_latencies');
    
    try {
      await ExperimentEventHelper.updateChatStats(
        uid: uid,
        eventId: eventId,
        chatId: chatId,
        totalTurns: _currentTurn,
        totalTokens: _totalTokens,
        avgLatencyMs: avgLatency,
      );
      debugPrint('聊天統計更新成功');
    } catch (e) {
      debugPrint('更新聊天統計失敗: $e');
      // 不要重新拋出錯誤，避免影響用戶體驗
    }
  }

  /// 生成并存储聊天总结
  Future<void> _generateAndSaveSummary() async {
    // 只有在有对话消息时才生成总结
    if (_messages.isEmpty || _messages.length < 2) {
      debugPrint('聊天消息太少，跳过总结生成');
      return;
    }

    try {
      debugPrint('開始生成聊天總結...');
      
      // 调用云函数获取总结
      final summaryResult = await _coach.summarizeChat(_messages);
      
      // 存储总结到 Firebase
      await ExperimentEventHelper.saveChatSummary(
        uid: uid,
        eventId: eventId,
        chatId: chatId,
        summary: summaryResult.summary,
        snoozeReasons: summaryResult.snoozeReasons,
        coachMethods: summaryResult.coachMethods,
      );
      
      debugPrint('聊天總結生成並存儲成功');
    } catch (e) {
      debugPrint('生成聊天總結失敗: $e');
      // 总结失败不影响用户体验，只记录错误
    }
  }
  
  /// 檢查用戶是否已表達開始任務的意願（用於判斷commit_plan）
  bool get hasCommitmentToPlan {
    // 簡單檢查最後幾條用戶消息是否包含肯定詞語
    final userMessages = _messages
        .where((msg) => msg.role == ChatRole.user)
        .map((msg) => msg.content.toLowerCase())
        .toList();
    
    if (userMessages.isEmpty) return false;
    
    // 檢查最後1-2條用戶消息是否包含承諾相關詞語
    final lastMessages = userMessages.take(2).join(' ');
    final commitmentKeywords = ['好', '開始', '做', '執行', '進行', '立即', '馬上', '現在', '確定', '決定'];
    
    return commitmentKeywords.any((keyword) => lastMessages.contains(keyword));
  }

  void reset() {
    _messages.clear();
    _currentTurn = 0; // 重置turn計數
    _hasStarted = false; // 重置開始狀態
    _latencies.clear(); // 重置延遲記錄
    _hasRecordedChatStart = false; // 重置記錄狀態
    _totalTokens = 0; // 重置token計數
    notifyListeners();
  }
}
