import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/proact_coach_service.dart';
import '../services/data_path_service.dart';

class ChatProvider extends ChangeNotifier {
  final _coach = ProactCoachService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  final String taskTitle;
  final String? taskDescription;
  final DateTime startTime;
  int _currentTurn = 0;
  bool _hasStarted = false;
  
  final String uid;
  final String eventId;
  final String chatId;
  final ChatEntryMethod entryMethod;
  final int? dayNumber; // 新增dayNumber參數
  final List<int> _latencies = [];
  bool _hasRecordedChatStart = false;
  int _totalTokens = 0;

  ChatProvider({
    required this.taskTitle, 
    this.taskDescription,
    required this.startTime,
    required this.uid,
    required this.eventId,
    required this.chatId,
    required this.entryMethod,
    this.dayNumber, // 新增dayNumber參數
  }) {
    _loadChatHistory(); // 加载历史聊天记录
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  int get currentTurn => _currentTurn;
  
  bool get isDialogueEnded {
    if (_messages.isEmpty) return false;
    final lastAssistantMessage = _messages.lastWhere(
      (msg) => msg.role == ChatRole.assistant,
      orElse: () => ChatMessage(role: ChatRole.assistant, content: ''),
    );
    return lastAssistantMessage.endOfDialogue;
  }

  String? get suggestedAction {
    if (_messages.isEmpty) return null;
    final lastAssistantMessage = _messages.lastWhere(
      (msg) => msg.role == ChatRole.assistant,
      orElse: () => ChatMessage(role: ChatRole.assistant, content: ''),
    );
    return lastAssistantMessage.extra?['suggested_action'];
  }

  /// 加载历史聊天记录
  Future<void> _loadChatHistory() async {
    try {
      final now = DateTime.now();
      final chatsCollection = await DataPathService.instance
          .getDateEventChatsCollection(uid, eventId, now);
      
      final snapshot = await chatsCollection
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp')
          .get();

      _messages.clear();
      _messages.addAll(snapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,
          role: ChatRole.values.firstWhere(
            (r) => r.toString() == data['role'],
            orElse: () => ChatRole.user,
          ),
          content: data['content'],
          endOfDialogue: data['endOfDialogue'] ?? false,
          extra: data['extra'] as Map<String, dynamic>?,
        );
      }));

      _currentTurn = _messages.length ~/ 2; // 每轮对话包含用户和助手各一条消息
      notifyListeners();
    } catch (e) {
      debugPrint('加载聊天历史失败: $e');
    }
  }

  /// 保存聊天消息到Firestore
  Future<void> _saveChatMessage(ChatMessage message) async {
    try {
      final now = DateTime.now();
      final chatsCollection = await DataPathService.instance
          .getDateEventChatsCollection(uid, eventId, now);
      
      await chatsCollection
          .doc(chatId)
          .collection('messages')
          .doc(message.id)
          .set({
        'role': message.role.toString(),
        'content': message.content,
        'timestamp': FieldValue.serverTimestamp(),
        'endOfDialogue': message.endOfDialogue,
        if (message.extra != null) 'extra': message.extra,
      });
    } catch (e) {
      debugPrint('保存聊天消息失败: $e');
    }
  }

  Future<void> sendUserMessage(String text) async {
    if (text.trim().isEmpty || isDialogueEnded) return;
    
    final userMessage = ChatMessage(
      id: const Uuid().v4(),
      role: ChatRole.user,
      content: text.trim(),
    );
    
    _messages.add(userMessage);
    _currentTurn++;
    notifyListeners();
    
    // 保存用户消息
    await _saveChatMessage(userMessage);
    
    // 获取助手回复
    await _fetchAssistantReply();
  }

  Future<void> _fetchAssistantReply() async {
    _isLoading = true;
    notifyListeners();

    final startTime = DateTime.now();

    try {
      final result = await _coach.getCompletion(
        _messages,
        taskTitle,
        this.startTime,
        _currentTurn,
        taskDescription: taskDescription,
        uid: uid,
        eventId: eventId,
        dayNumber: dayNumber, // 新增dayNumber參數
      );
      
      _messages.add(result.message);
      
      // 保存助手消息
      await _saveChatMessage(result.message);
      
      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMilliseconds;
      _latencies.add(latencyMs);
      _totalTokens += result.totalTokens;
      
      debugPrint('本轮token: ${result.totalTokens}, 累积token: $_totalTokens');
    } catch (e) {
      debugPrint('_fetchAssistantReply错误: $e');
      final errorMessage = ChatMessage(
        id: const Uuid().v4(),
        role: ChatRole.assistant,
        content: '⚠️ 发生错误，请稍后再试',
      );
      _messages.add(errorMessage);
      await _saveChatMessage(errorMessage);
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
          entryMethod: entryMethod, // 🎯 新增：傳遞進入方式
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

  bool _hasEndedChat = false; // 标记是否已经结束聊天

  /// 結束聊天會話並記錄實驗數據
  Future<void> endChatSession(ChatResult result, {bool commitPlan = false}) async {
    if (!_hasRecordedChatStart || _hasEndedChat) return; // 如果没有开始记录或已经结束，就不再记录
    
    try {
      // 获取AI回应中的commit plan文本
      String? commitPlanText;
      if (commitPlan && _messages.isNotEmpty) {
        // 查找最后一条有commit_plan的AI消息
        final lastAssistantMessage = _messages.lastWhere(
          (msg) => msg.role == ChatRole.assistant && msg.extra?['commit_plan'] != null,
          orElse: () => ChatMessage(role: ChatRole.assistant, content: ''),
        );
        commitPlanText = lastAssistantMessage.extra?['commit_plan'];
      }
      
      // 記錄聊天結束
      await ExperimentEventHelper.recordChatEnd(
        uid: uid,
        eventId: eventId,
        chatId: chatId,
        result: result.value,
        commitPlan: commitPlanText ?? '',
      );
      
      // 更新統計數據
      await _updateChatStatistics();
      
      // 🎯 新增：生成並儲存聊天總結
      await _generateAndSaveSummary();
      
      _hasEndedChat = true; // 标记聊天已结束
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

  /// 生成並儲存聊天總結
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
      
      // 儲存總結到 Firebase
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
    _hasEndedChat = false; // 重置结束状态
    _totalTokens = 0; // 重置token計數
    notifyListeners();
  }
}
