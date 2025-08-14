import '../models/chat_message.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/data_path_service.dart';
import '../models/daily_report_model.dart';

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

/// 前一天的数据，包含聊天总结和日报
class YesterdayData {
  final String? chatSummary;
  final List<String> allChatSummaries; // 新增：最近一天的所有聊天总结
  final String? dailyReportSummary;
  final String? yesterdayStatus;
  
  YesterdayData({
    this.chatSummary,
    this.allChatSummaries = const [],
    this.dailyReportSummary,
    this.yesterdayStatus,
  });
}

class ProactCoachService {
  final _fn = FirebaseFunctions.instance
      .httpsCallable('procrastination_coach_completion');
  final _summarizeFn = FirebaseFunctions.instance
      .httpsCallable('summarize_chat');

  /// 获取最近一天的聊天总结和日报数据
  Future<YesterdayData> getYesterdayData(String uid, String eventId) async {
    try {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      
      // 获取最近有聊天的日期的聊天总结（包括今天）
      String? chatSummary;
      List<String> allChatSummaries = [];
      DateTime? recentChatDate;
      try {
        // 取得 w1 / w2 事件集合
        final w1Col = await DataPathService.instance.getUserW1EventsCollection(uid);
        final w2Col = await DataPathService.instance.getUserW2EventsCollection(uid);
        final w1Events = await w1Col.get();
        final w2Events = await w2Col.get();
        // 合併所有事件
        final allEvents = <DocumentSnapshot>[];
        allEvents.addAll(w1Events.docs);
        allEvents.addAll(w2Events.docs);
        
        // 查找最近有聊天总结的事件
        final summaries = <String>[];
        final allSummaries = <String>[];
        DateTime? latestSummaryDate;
        
        for (final eventDoc in allEvents) {
          try {
            final chatsCollection = eventDoc.reference.collection('chats');
            // 获取所有有总结的聊天记录，不限制数量
            final chatsWithSummary = await chatsCollection
                .where('summary_created_at', isGreaterThan: null)
                .orderBy('summary_created_at', descending: true)
                .get();
            
            for (final chatDoc in chatsWithSummary.docs) {
              final chatData = chatDoc.data();
              final summary = chatData['summary'] as String?;
              final summaryCreatedAt = chatData['summary_created_at'] as Timestamp?;
              
              if (summary != null && summary.isNotEmpty && summaryCreatedAt != null) {
                final summaryDate = summaryCreatedAt.toDate();
                
                // 考虑昨天及之前的总结，以及今天的总结
                if (summaryDate.isBefore(DateTime.now().add(const Duration(hours: 1)))) {
                  // 记录所有符合条件的总结
                  allSummaries.add(summary);
                  
                  // 找到最新的总结日期
                  if (latestSummaryDate == null || summaryDate.isAfter(latestSummaryDate)) {
                    latestSummaryDate = summaryDate;
                    summaries.clear(); // 清除之前的总结，只保留最新的
                    summaries.add(summary);
                  }
                }
              }
            }
          } catch (e) {
            // 忽略单个事件的错误，继续处理其他事件
            print('处理事件 ${eventDoc.id} 的聊天总结时出错: $e');
          }
        }
        
        // 如果有找到总结，使用最新的
        if (summaries.isNotEmpty) {
          chatSummary = summaries.first;
          recentChatDate = latestSummaryDate;
          
          // 获取最近一天的所有聊天总结
          if (latestSummaryDate != null) {
            final targetDate = latestSummaryDate;
            final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
            final endOfDay = startOfDay.add(const Duration(days: 1));
            
            // 重新遍历所有事件，获取指定日期的所有聊天总结
            for (final eventDoc in allEvents) {
              try {
                final chatsCollection = eventDoc.reference.collection('chats');
                final chatsInDay = await chatsCollection
                    .where('summary_created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
                    .where('summary_created_at', isLessThan: Timestamp.fromDate(endOfDay))
                    .orderBy('summary_created_at', descending: true)
                    .get();
                
                for (final chatDoc in chatsInDay.docs) {
                  final chatData = chatDoc.data();
                  final summary = chatData['summary'] as String?;
                  
                  if (summary != null && summary.isNotEmpty) {
                    allChatSummaries.add(summary);
                  }
                }
                print('allChatSummaries: ${allChatSummaries}');
              } catch (e) {
                print('获取指定日期的聊天总结时出错: $e');
              }
            }
          }
          
          final isToday = recentChatDate?.day == DateTime.now().day && 
                          recentChatDate?.month == DateTime.now().month && 
                          recentChatDate?.year == DateTime.now().year;
          final dateType = isToday == true ? '今天' : '之前';
          print('找到最近聊天总结，日期: ${recentChatDate?.toLocal()} ($dateType)，当天总结数量: ${allChatSummaries.length}');
        }
      } catch (e) {
        print('获取最近聊天总结失败: $e');
      }
      
      // 获取最近一天的日报（基于聊天总结的日期）
      String? dailyReportSummary;
      String? yesterdayStatus;
      try {
        // 如果有找到聊天总结，使用对应的日期；否则使用昨天的日期
        final targetDate = recentChatDate ?? yesterday;
        final targetDateStr = '${targetDate.year}${targetDate.month.toString().padLeft(2, '0')}${targetDate.day.toString().padLeft(2, '0')}';
        
        final dailyReportCollection = await DataPathService.instance.getUserDailyReportCollection(uid, targetDateStr);
        final dailyReports = await dailyReportCollection.get();
        
        if (dailyReports.docs.isNotEmpty) {
          final report = DailyReportModel.fromDoc(dailyReports.docs.first);
          
          // 构建日报摘要
          final summaryParts = <String>[];
          if (report.notes != null && report.notes!.isNotEmpty) {
            summaryParts.add('心得: ${report.notes}');
          }
          if (report.aiImprovementSuggestions != null && report.aiImprovementSuggestions!.isNotEmpty) {
            summaryParts.add('Coach改進建議: ${report.aiImprovementSuggestions}');
          }
          
          dailyReportSummary = summaryParts.isNotEmpty ? summaryParts.join('; ') : null;
          
          // 构建状态摘要
          final statusParts = <String>[];
          if (report.delayedTaskIds.isNotEmpty) {
            statusParts.add('延遲任務: ${report.delayedTaskIds.length}個');
          }
          if (report.delayReasons.isNotEmpty) {
            statusParts.add('延遲原因: ${report.delayReasons.join(', ')}');
          }          
          yesterdayStatus = statusParts.join('; ');
          
          print('找到对应日期的日报，日期: ${targetDate.toLocal()}');
        } else {
          print('未找到对应日期的日报，日期: ${targetDate.toLocal()}');
        }
      } catch (e) {
        print('获取最近日报失败: $e');
      }
      
      return YesterdayData(
        chatSummary: chatSummary,
        allChatSummaries: allChatSummaries,
        dailyReportSummary: dailyReportSummary,
        yesterdayStatus: yesterdayStatus,
      );
    } catch (e) {
      print('获取前一天数据失败: $e');
      return YesterdayData();
    }
  }

  Future<ChatCompletionResult> getCompletion(
      List<ChatMessage> history, String taskTitle, DateTime startTime, int currentTurn, {String? taskDescription, String? uid, String? eventId, int? dayNumber, int? taskDurationMin}) async {
    // 获取前一天的数据
    YesterdayData? yesterdayData;
    if (uid != null && eventId != null) {
      yesterdayData = await getYesterdayData(uid, eventId);
    }
    
    // 把 ChatMessage 轉成 Cloud Function 需要的 Map
    final mapped = history
        .map((m) => {'role': _roleToString(m.role), 'content': m.content})
        .toList();
    
    // 格式化開始時間為台灣時區
    final taiwanTime = startTime.toLocal();
    final formattedStartTime = '${taiwanTime.year}-${taiwanTime.month.toString().padLeft(2, '0')}-${taiwanTime.day.toString().padLeft(2, '0')} ${taiwanTime.hour.toString().padLeft(2, '0')}:${taiwanTime.minute.toString().padLeft(2, '0')}';
    
    // 合并所有聊天总结
    String combinedChatSummary = '';
    if (yesterdayData?.allChatSummaries.isNotEmpty == true) {
      if (yesterdayData!.allChatSummaries.length == 1) {
        combinedChatSummary = yesterdayData.allChatSummaries.first;
      } else {
        // 如果有多个聊天总结，按时间顺序合并
        combinedChatSummary = yesterdayData.allChatSummaries.asMap().entries
            .map((entry) => '聊天${entry.key + 1}: ${entry.value}')
            .join('\n\n');
      }
    } else {
      // 如果没有获取到所有聊天总结，使用单个总结作为备选
      combinedChatSummary = yesterdayData?.chatSummary ?? '';
    }
    
    print('current turn: ${currentTurn}');
    print('yesterday data: ${yesterdayData?.chatSummary}, ${yesterdayData?.dailyReportSummary}');
    print('all chat summaries count: ${yesterdayData?.allChatSummaries.length ?? 0}');
    
    final res = await _fn.call({
      'taskTitle': taskTitle, 
      'taskDescription': taskDescription, // 新增描述參數
      'dialogues': mapped,
      'startTime': formattedStartTime,
      'currentTurn': currentTurn,
      'dayNumber': dayNumber, // 新增dayNumber參數
      'taskDurationMin': taskDurationMin, // 新增任務時長（分鐘）
      'yesterdayChat': combinedChatSummary,
      'yesterdayStatus': yesterdayData?.yesterdayStatus ?? '',
      'dailySummary': yesterdayData?.dailyReportSummary ?? '',
    });
    
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
      // 安全地轉換並提取total_tokens
      if (tokenUsageRaw is Map) {
        totalTokens = (tokenUsageRaw['total_tokens'] as num?)?.toInt() ?? 0;
      }
    }
    
    // 🎯 調試：檢查answer內容
    final answerContent = res.data['answer'];
    print('Raw answer content: "$answerContent"');
    print('Suggested action: $suggestedAction');
    
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: answerContent?.toString() ?? '⚠️ 無法獲取回應內容',
      endOfDialogue: endOfDialogue,
      extra: {
        'suggested_action': suggestedAction,
        if (commitPlan != null && commitPlan.toString().isNotEmpty) 'commit_plan': commitPlan.toString(),
      },
    );
   
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
