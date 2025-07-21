import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/task_start_dialog.dart';
import '../navigation_service.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/auth_service.dart';
import '../services/app_usage_service.dart';
import '../screens/daily_report_screen.dart';
import '../screens/chat_screen.dart'; // Added import for ChatScreen

class NotificationHandler {
  NotificationHandler._();
  static final instance = NotificationHandler._();
  
  // 记录已显示过完成对话框的任务ID
  final Set<String> _shownCompletionDialogTaskIds = {};
  
  // 全局TaskStartDialog显示状态管理
  bool _isTaskStartDialogShowing = false;
  
  /// 检查是否有TaskStartDialog正在显示
  bool get isTaskStartDialogShowing => _isTaskStartDialogShowing;
  
  /// 设置TaskStartDialog显示状态
  void setTaskStartDialogShowing(bool showing) {
    _isTaskStartDialogShowing = showing;
    if (kDebugMode) {
      print('TaskStartDialog显示状态: $showing');
    }
  }
  
  /// 检查当前是否在聊天页面
  bool _isInChatScreen() {
    final context = NavigationService.context;
    if (context == null) return false;
    
    // 通过查找ChatScreen来判断是否在聊天页面
    try {
      return context.findAncestorWidgetOfExactType<ChatScreen>() != null;
    } catch (e) {
      return false;
    }
  }
  
  /// 获取已显示过完成对话框的任务ID
  Set<String> get shownCompletionDialogTaskIds => Set.from(_shownCompletionDialogTaskIds);
  
  /// 清理已完成或已开始的任务ID
  void cleanupCompletionDialogTaskIds(List<String> eventIds) {
    _shownCompletionDialogTaskIds.removeWhere((taskId) => !eventIds.contains(taskId));
  }

  /// 處理通知點擊事件
  Future<void> handleNotificationTap(String? payload) async {
    if (payload == null || payload.isEmpty) {
      if (kDebugMode) {
        print('通知 payload 為空');
      }
      return;
    }

    try {
      if (kDebugMode) {
        print('處理通知點擊，payload: $payload');
      }

      // 特殊處理每日報告通知
      if (payload == 'daily_report') {
        await _handleDailyReportNotification();
        return;
      }

      // 特殊處理任務完成提醒通知
      if (payload.startsWith('task_completion_')) {
        final eventId = payload.replaceFirst('task_completion_', '');
        await _handleTaskCompletionNotification(eventId);
        return;
      }

      // 根據事件ID獲取事件資料
      final event = await _getEventById(payload);
      if (event == null) {
        if (kDebugMode) {
          print('找不到事件: $payload');
        }
        return;
      }

      // 檢查事件狀態
      if (event.isDone) {
        if (kDebugMode) {
          print('事件已完成，不顯示彈窗: ${event.title}');
        }
        return;
      }

      if (event.actualStartTime != null) {
        if (kDebugMode) {
          print('事件已開始，不顯示彈窗: ${event.title}');
        }
        return;
      }

      // 🎯 實驗數據收集：記錄通過通知打開應用
      AppUsageService.instance.recordAppOpen(fromNotification: true);

      // 🎯 實驗數據收集：記錄通知點擊
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        if (kDebugMode) {
          print('🎯 記錄通知點擊: eventId=${event.id}, notifIds=${event.notifIds}');
        }
        
        await ExperimentEventHelper.recordNotificationTap(
          uid: currentUser.uid,
          eventId: event.id,
        );

        // 🎯 實驗數據收集：記錄通知被打開（對所有可能的通知ID）
        for (final notifId in event.notifIds) {
          if (kDebugMode) {
            print('🎯 記錄通知被打開: notifId=$notifId');
          }
          await ExperimentEventHelper.recordNotificationOpened(
            uid: currentUser.uid,
            eventId: event.id,
            notifId: notifId,
          );
        }
      }

      // 顯示任務開始彈窗
      await _showTaskStartDialog(event);

    } catch (e) {
      if (kDebugMode) {
        print('處理通知點擊時發生錯誤: $e');
      }
    }
  }

  /// 根據事件ID獲取事件資料
  Future<EventModel?> _getEventById(String eventId) async {
    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('無法獲取當前用戶');
        }
        return null;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('events')
          .doc(eventId)
          .get();

      if (!doc.exists) {
        if (kDebugMode) {
          print('事件不存在: $eventId');
        }
        return null;
      }

      return EventModel.fromDoc(doc);
    } catch (e) {
      if (kDebugMode) {
        print('獲取事件資料失敗: $e');
      }
      return null;
    }
  }

  /// 顯示任務開始彈窗
  Future<void> _showTaskStartDialog(EventModel event) async {
    // 检查是否已有TaskStartDialog在显示
    if (_isTaskStartDialogShowing) {
      if (kDebugMode) {
        print('已有TaskStartDialog在顯示，跳過: ${event.title}');
      }
      return;
    }
    
    // 检查是否在聊天页面
    if (_isInChatScreen()) {
      if (kDebugMode) {
        print('當前在聊天頁面，不顯示TaskStartDialog: ${event.title}');
      }
      return;
    }
    
    final context = NavigationService.context;
    if (context == null) {
      if (kDebugMode) {
        print('無法獲取 NavigationService 的 context');
      }
      return;
    }

    // 設置對話框顯示狀態
    setTaskStartDialogShowing(true);

    // 確保在主線程中執行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => TaskStartDialog(event: event),
        ).then((_) {
          // 對話框關閉時重置狀態
          setTaskStartDialogShowing(false);
        });
      } else {
        // 如果context不可用，重置狀態
        setTaskStartDialogShowing(false);
      }
    });

    if (kDebugMode) {
      print('顯示任務開始彈窗: ${event.title}');
    }
  }

  /// 處理每日報告通知點擊
  Future<void> _handleDailyReportNotification() async {
    try {
      // 記錄應用打開事件（由通知觸發）
      await AppUsageService.instance.recordAppOpen(
        fromNotification: true,
      );

      if (kDebugMode) {
        print('每日報告通知被點擊，準備導航到每日報告頁面');
      }

      // 導航到每日報告頁面
      final context = NavigationService.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        // 確保在主線程中執行
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DailyReportScreen(),
              ),
            );
          }
        });
      } else {
        if (kDebugMode) {
          print('無法獲取有效的 BuildContext 來導航');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('處理每日報告通知時發生錯誤: $e');
      }
    }
  }

  /// 處理任務完成提醒通知點擊
  Future<void> _handleTaskCompletionNotification(String eventId) async {
    try {
      // 記錄應用打開事件（由通知觸發）
      await AppUsageService.instance.recordAppOpen(
        fromNotification: true,
      );

      if (kDebugMode) {
        print('任務完成提醒通知被點擊: $eventId');
      }

      // 獲取事件資料
      final event = await _getEventById(eventId);
      if (event == null) {
        if (kDebugMode) {
          print('找不到事件: $eventId');
        }
        return;
      }

      // 檢查事件是否已完成
      if (event.isDone) {
        if (kDebugMode) {
          print('事件已完成: ${event.title}');
        }
        return;
      }

      // 记录已显示过完成对话框的任务ID
      _shownCompletionDialogTaskIds.add(event.id);

      // 顯示完成確認對話框
      await _showCompletionDialog(event);

    } catch (e) {
      if (kDebugMode) {
        print('處理任務完成提醒通知時發生錯誤: $e');
      }
    }
  }

  /// 顯示任務完成確認對話框
  Future<void> _showCompletionDialog(EventModel event) async {
    final context = NavigationService.context;
    if (context == null) {
      if (kDebugMode) {
        print('無法獲取 NavigationService 的 context');
      }
      return;
    }

    // 確保在主線程中執行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            title: const Text('任務時間到了'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('「${event.title}」的預計時間已結束，您已經完成這個任務了嗎？'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('稍後再說'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // 執行完成操作
                  await _completeTask(event);
                },
                child: const Text('已完成'),
              ),
            ],
          ),
        );
      }
    });

    if (kDebugMode) {
      print('顯示任務完成確認對話框: ${event.title}');
    }
  }

  /// 執行任務完成操作
  Future<void> _completeTask(EventModel event) async {
    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) return;

      // 更新事件為已完成
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('events')
          .doc(event.id)
          .update({
        'isDone': true,
        'completedTime': Timestamp.fromDate(DateTime.now()),
        'status': TaskStatus.completed.value,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      if (kDebugMode) {
        print('任務已標記為完成: ${event.title}');
      }

      // 記錄實驗數據
      await ExperimentEventHelper.recordEventCompletion(
        uid: currentUser.uid,
        eventId: event.id,
      );

    } catch (e) {
      if (kDebugMode) {
        print('完成任務時發生錯誤: $e');
      }
    }
  }
} 