import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../screens/chat_screen.dart';
import '../providers/chat_provider.dart';

class TaskStartDialog extends StatelessWidget {
  final EventModel event;
  
  const TaskStartDialog({
    super.key,
    required this.event,
  });

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
                const Text(
                  'Start the Task',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '"${event.title}"',
                  style: const TextStyle(
                    fontSize: 20,
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
                    onPressed: () {
                      Navigator.of(context).pop();
                      _startTask(context);
                      _recordNotificationResult(context, NotificationResult.start);
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
                    child: const Text(
                      '現在開始',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
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
                        final chatId = ExperimentEventHelper.generateChatId(event.id, DateTime.now());
                        
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider(
                              create: (_) => ChatProvider(
                                taskTitle: event.title, 
                                startTime: event.scheduledStartTime,
                                uid: uid,
                                eventId: event.id,
                                chatId: chatId,
                                entryMethod: ChatEntryMethod.notification, // 🎯 新增：通知進入
                              ),
                              child: ChatScreen(taskTitle: event.title),
                            ),
                          ),
                        );
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
                      '等等再說',
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
  void _startTask(BuildContext context) async {
    try {
      // 執行開始任務邏輯
      final uid = context.read<AuthService>().currentUser?.uid;
      if (uid == null) {
        _showErrorMessage(context, '用戶未登入');
        return;
      }

      await CalendarService.instance.startEvent(uid, event);
      
      // 顯示成功訊息
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('任務「${event.title}」已開始'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
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
        final chatId = ExperimentEventHelper.generateChatId(event.id, DateTime.now());
        
        await ExperimentEventHelper.recordChatTrigger(
          uid: currentUser.uid,
          eventId: event.id,
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
        // 對所有可能的通知ID記錄結果
        for (final notifId in event.notifIds) {
          ExperimentEventHelper.recordNotificationResult(
            uid: currentUser.uid,
            eventId: event.id,
            notifId: notifId,
            result: result,
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