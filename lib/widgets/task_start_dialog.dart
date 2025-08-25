import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../screens/chat_screen.dart';
import '../providers/chat_provider.dart';
import '../services/analytics_service.dart';
import '../services/task_router_service.dart';
import '../services/vocab_service.dart';
import '../navigation_service.dart';
import '../screens/vocab_page.dart';
import '../screens/reading_page.dart';

class TaskStartDialog extends StatefulWidget {
  final EventModel event;
  // 新增：當前被點擊的notifId（若有）
  final String? notifId;
  final bool isControlGroup;

  const TaskStartDialog({
    super.key,
    required this.event,
    this.notifId,
    this.isControlGroup = false,
  });

  @override
  State<TaskStartDialog> createState() => _TaskStartDialogState();
}

class _TaskStartDialogState extends State<TaskStartDialog> {
  bool _isOpeningChat = false; // 防止重複點擊聊天按鈕
  bool _isStartingTask = false; // 防止重複點擊開始任務按鈕

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題部分
            Column(
              children: [
                Text(
                  '準備好開始"${widget.event.title}"了嗎？',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (!widget.isControlGroup)
                  const Text(
                    '需不需要跟我聊聊，讓我陪你一起開始這個任務呢？',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
            const SizedBox(height: 40),
            // 按鈕部分
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isStartingTask ? null : () async {
                      // 防止重複點擊
                      if (_isStartingTask) return;
                      setState(() {
                        _isStartingTask = true;
                      });
                      
                      try {
                        // 直接開始任務並導頁；避免先 pop 導致 context/mounted 問題
                        await _startTask(context);
                        _recordNotificationResult(context, NotificationResult.start);
                      } finally {
                        // 確保無論成功或失敗都重置狀態
                        if (mounted) {
                          setState(() {
                            _isStartingTask = false;
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8B4CB), // 粉紅色
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isStartingTask 
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '啟動中...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          '開始任務',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: widget.isControlGroup
                      ? ElevatedButton(
                          onPressed: () {
                            _recordNotificationResult(context, NotificationResult.snooze);
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300], // 灰色
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            '等等再說',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: _isOpeningChat
                              ? null
                              : () async {
                                  // 防止重複點擊
                                  _isOpeningChat = true;

                                  try {
                                    // 先獲取父級navigator，再關閉對話框
                                    final navigator = Navigator.of(context);
                                    final parentContext = context;

                                    // 先執行實驗數據收集
                                    await _recordChatStart(parentContext);

                                    // 記錄通知結果為延後處理
                                    _recordNotificationResult(parentContext, NotificationResult.snooze);

                                    // 關閉對話框
                                    navigator.pop();

                                    // 導航到聊天頁面
                                    final uid = parentContext.read<AuthService>().currentUser?.uid;
                                    if (uid != null) {
                                      // 根據事件標題解析週/日 counts，組合 taskDescription
                                      String? enrichedDesc = widget.event.description;
                                      int? durationMin;
                                      try {
                                        final start = widget.event.scheduledStartTime;
                                        final end = widget.event.scheduledEndTime;
                                        durationMin = end.difference(start).inMinutes;
                                      } catch (_) {}

                                      try {
                                        final svc = VocabService();
                                        final wd = svc.parseWeekDayFromTitle(widget.event.title);
                                        if (wd != null) {
                                          final counts = await svc.loadWeeklyCounts(wd[0], wd[1]);
                                          final newCnt = counts['new'] ?? 0;
                                          final reviewCnt = counts['review'] ?? 0;
                                          enrichedDesc = 'vocab — new=${newCnt}, review=${reviewCnt}';
                                        }
                                      } catch (e) {
                                        debugPrint('讀取vocab counts失敗: $e');
                                      }
                                      final chatId = ExperimentEventHelper.generateChatId(widget.event.id, DateTime.now());

                                      navigator.push(
                                        MaterialPageRoute(
                                          builder: (_) => ChangeNotifierProvider(
                                            create: (_) => ChatProvider(
                                              taskTitle: widget.event.title,
                                              taskDescription: enrichedDesc, // 帶入 new/review
                                              startTime: widget.event.scheduledStartTime,
                                              uid: uid,
                                              eventId: widget.event.id,
                                              chatId: chatId,
                                              entryMethod: ChatEntryMethod.notification,
                                              dayNumber: widget.event.dayNumber,
                                              taskDurationMin: durationMin,
                                            ),
                                            child: ChatScreen(
                                              taskTitle: widget.event.title,
                                              taskDescription: enrichedDesc,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  } finally {
                                    // 重置標記
                                    _isOpeningChat = false;
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB8E6B8), // 綠色
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            '不太想開始',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 開始任務
  Future<void> _startTask(BuildContext context) async {
    try {
      // 執行開始任務邏輯
      final uid = context.read<AuthService>().currentUser?.uid;
      if (uid == null) {
        _showErrorMessage(context, '用戶未登入');
        return;
      }

      await CalendarService.instance.startEvent(uid, widget.event);
      
      // 記錄分析事件 - 改由 TaskRouterService 统一记录
      // await AnalyticsService().logTaskStarted('dialog');
      
      // 顯示成功訊息
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('任務「${widget.event.title}」已開始'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
        
        // 先關閉對話框
        Navigator.of(context).pop();

        // 使用路由服務判斷任務型別並導頁（含 test 類型）
        final navContext = NavigationService.context ?? context;
        if (navContext.mounted) {
          TaskRouterService().navigateToTaskPage(navContext, widget.event, source: 'notification_dialog');
        } else {
          // 後備：若 navContext 不可用，直接嘗試用全域 navigator push
          TaskRouterService().navigateToTaskPage(context, widget.event, source: 'notification_dialog');
        }
      }
    } catch (e) {
      _showErrorMessage(context, '開始任務失敗: $e');
    }
  }

  /// 記錄聊天開始的實驗數據
  Future<void> _recordChatStart(BuildContext context) async {
    try {
      // 🎯 實驗數據收集：生成聊天ID並記錄聊天觸發（不開始任務）
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser != null) {
        final chatId = ExperimentEventHelper.generateChatId(widget.event.id, DateTime.now());
        
        await ExperimentEventHelper.recordChatTrigger(
          uid: currentUser.uid,
                      eventId: widget.event.id,
          chatId: chatId,
        );
      }
    } catch (e) {
      // 如果實驗數據記錄失敗，不影響用戶體驗，只記錄錯誤
      debugPrint('記錄聊天開始數據失敗: $e');
    }
  }

  /// 記錄通知操作結果的實驗數據
  void _recordNotificationResult(BuildContext context, NotificationResult result) {
    try {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser != null) {
        // 若能辨識被點擊的通知，則只記錄該筆；否則保底記第一個
        final targetNotifId = widget.notifId ?? (widget.event.notifIds.isNotEmpty ? widget.event.notifIds.first : null);
        if (targetNotifId != null) {
          ExperimentEventHelper.recordNotificationResult(
            uid: currentUser.uid,
            eventId: widget.event.id,
            notifId: targetNotifId,
            result: result,
            eventDate: widget.event.date,
          );
        }
      }
    } catch (e) {
      // 如果實驗數據記錄失敗，不影響用戶體驗，只記錄錯誤
      debugPrint('記錄通知結果數據失敗: $e');
    }
  }



  /// 顯示錯誤訊息
  void _showErrorMessage(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
} 