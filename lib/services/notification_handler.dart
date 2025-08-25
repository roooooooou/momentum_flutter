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
import 'package:momentum/services/data_path_service.dart';
import 'package:momentum/services/experiment_config_service.dart';
import 'analytics_service.dart';

class NotificationHandler {
  NotificationHandler._();
  static final instance = NotificationHandler._();
  
  // 记录已显示过完成对话框的任务ID
  final Set<String> _shownCompletionDialogTaskIds = {};
  
  // 全局TaskStartDialog显示状态管理
  bool _isTaskStartDialogShowing = false;
  
  // 🎯 新增：追蹤是否有通知觸發的 dialog 正在顯示
  bool _isNotificationTriggeredDialogShowing = false;
  
  // 🎯 新增：記錄最後一次通知觸發的時間
  DateTime? _lastNotificationTriggerTime;
  
  /// 检查是否有TaskStartDialog在显示
  bool get isTaskStartDialogShowing => _isTaskStartDialogShowing;
  
  /// 🎯 新增：檢查是否有通知觸發的 dialog 正在顯示
  bool get isNotificationTriggeredDialogShowing => _isNotificationTriggeredDialogShowing;
  
  /// 🎯 新增：獲取最後一次通知觸發的時間
  DateTime? get lastNotificationTriggerTime => _lastNotificationTriggerTime;
  
  /// 🎯 新增：檢查是否在通知觸發的時間窗口內（預設 30 秒）
  bool isInNotificationTriggerWindow({Duration window = const Duration(seconds: 10)}) {
    if (_lastNotificationTriggerTime == null) return false;
    final now = DateTime.now();
    final timeSinceLastNotification = now.difference(_lastNotificationTriggerTime!);
    return timeSinceLastNotification < window;
  }
  
  /// 设置TaskStartDialog显示状态
  void setTaskStartDialogShowing(bool showing) {
    _isTaskStartDialogShowing = showing;
    if (kDebugMode) {
      print('TaskStartDialog显示状态: $showing');
    }
  }
  
  /// 🎯 新增：設置通知觸發的 dialog 顯示狀態
  void setNotificationTriggeredDialogShowing(bool showing) {
    _isNotificationTriggeredDialogShowing = showing;
    if (kDebugMode) {
      print('通知觸發的 TaskStartDialog 顯示狀態: $showing');
    }
  }
  
  /// 检查当前是否在聊天页面
  bool _isInChatScreen() {
    final context = NavigationService.context;
    if (context == null) return false;
    
    // 通过查找ChatScreen来判断是否在聊天页面
    try {
      final isInChat = context.findAncestorWidgetOfExactType<ChatScreen>() != null;
      if (kDebugMode) {
        print('检查是否在聊天页面: $isInChat');
      }
      return isInChat;
    } catch (e) {
      if (kDebugMode) {
        print('检查聊天页面状态时出错: $e');
      }
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
  Future<void> handleNotificationTap(String? payload, {bool forceShow = false}) async {
    if (payload == null || payload.isEmpty) {
      if (kDebugMode) {
        print('通知 payload 為空');
      }
      return;
    }

    // 預先宣告以便在錯誤重試時可使用
    String? parsedEventId;
    String? clickedNotifId;

    // 确保应用已完全启动
    if (NavigationService.context == null) {
      if (kDebugMode) {
        print('应用尚未完全启动，等待...');
      }
      // 等待应用启动
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (NavigationService.context != null) {
          if (kDebugMode) {
            print('应用已启动，继续处理通知');
          }
          break;
        }
      }
      if (NavigationService.context == null) {
        if (kDebugMode) {
          print('应用启动超时，无法处理通知');
        }
        return;
      }
    }

    try {
      if (kDebugMode) {
        print('處理通知點擊，payload: $payload');
      }

      // 根據 payload 類型記錄 notification_open 事件
      String notificationType;
      String? eventIdForAnalytics;

      if (payload == 'daily_report') {
        notificationType = 'daily_report';
      } else if (payload.startsWith('task_completion_')) {
        notificationType = 'task_completion';
        eventIdForAnalytics = payload.replaceFirst('task_completion_', '');
      } else {
        notificationType = 'task_reminder';
        final match = RegExp(r'^(.*)-(1st|2nd)$').firstMatch(payload);
        eventIdForAnalytics = match != null ? match.group(1) : payload;
      }

      // 檢查使用者分組
      final currentUser = AuthService.instance.currentUser;
      bool isControlGroup = false;
      if (currentUser != null) {
        isControlGroup = await ExperimentConfigService.instance.isControlGroup(currentUser.uid);
      }
      final userGroup = isControlGroup ? 'control' : 'experiment';

      AnalyticsService().logNotificationOpen(
        userGroup: userGroup,
        notificationType: notificationType,
        eventId: eventIdForAnalytics,
      );

      // 特殊處理每日報告通知
      if (payload == 'daily_report') {
        await _handleDailyReportNotification();
        return;
      }

      // 🎯 已移除：任務完成提醒通知處理
      // 不再需要，因為已移除該功能

      // 一般事件通知：payload 可能為 eventId 或 "eventId-1st/2nd"
      String eventId = payload;
      final match = RegExp(r'^(.*)-(1st|2nd)$').firstMatch(payload);
      if (match != null) {
        eventId = match.group(1)!;
        clickedNotifId = payload; // 完整的notifId
        
        // 🎯 調試：詳細記錄第二個通知的處理
        if (kDebugMode) {
          print('🎯 檢測到第二個通知:');
          print('🎯 Original payload: $payload');
          print('🎯 Parsed eventId: $eventId');
          print('🎯 Clicked notifId: $clickedNotifId');
          print('🎯 Match groups: ${match.groups([1, 2])}');
        }
      } else {
        // 🎯 調試：記錄第一個通知的處理
        if (kDebugMode) {
          print('🎯 檢測到第一個通知或直接事件ID:');
          print('🎯 Original payload: $payload');
          print('🎯 Parsed eventId: $eventId');
          print('🎯 Clicked notifId: $clickedNotifId');
        }
      }
      parsedEventId = eventId;

      // 根據事件ID獲取事件資料
      final event = await _getEventById(eventId);
      if (event == null) {
        if (kDebugMode) {
          print('找不到事件: $eventId');
        }
        return;
      }
      
      // 🎯 調試：驗證獲取到的事件信息
      if (kDebugMode) {
        print('🎯 NotificationHandler: 獲取到事件');
        print('🎯 Event ID: ${event.id}');
        print('🎯 Event Title: ${event.title}');
        print('🎯 Event Date: ${event.date}');
        print('🎯 Event DayNumber: ${event.dayNumber}');
        print('🎯 Original payload: $payload');
        print('🎯 Parsed eventId: $eventId');
        print('🎯 Clicked notifId: $clickedNotifId');
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

      // 🎯 特殊處理：test 任務不顯示 task start dialog
      if (event.title.toLowerCase().contains('test')) {
        if (kDebugMode) {
          print('🎯 test 任務不顯示 task start dialog: ${event.title}');
        }
        // 記錄通知點擊但不顯示對話框
        if (currentUser != null) {
          await ExperimentEventHelper.recordNotificationTap(
            uid: currentUser.uid,
            eventId: event.id,
          );
        }
        return;
      }

      // 🎯 實驗數據收集：記錄通過通知打開應用
      AppUsageService.instance.recordAppOpen(fromNotification: true);

      // 🎯 實驗數據收集：記錄通知點擊
      if (currentUser != null) {
        if (kDebugMode) {
          print('🎯 記錄通知點擊: eventId=${event.id}, clickedNotifId=${clickedNotifId ?? 'unknown'}');
        }
        
        await ExperimentEventHelper.recordNotificationTap(
          uid: currentUser.uid,
          eventId: event.id,
        );

        // 🎯 實驗數據收集：只記錄被點擊的那一則通知為 opened（若可辨識）
        final notifToRecord = clickedNotifId ?? (event.notifIds.isNotEmpty ? event.notifIds.first : null);
        if (notifToRecord != null) {
          if (kDebugMode) {
            print('🎯 記錄通知被打開: notifId=$notifToRecord');
          }
          await ExperimentEventHelper.recordNotificationOpened(
            uid: currentUser.uid,
            eventId: event.id,
            notifId: notifToRecord,
            eventDate: event.date, // 🎯 传递事件发生的日期
          );
        }

        // 🎯 检查用户组：对照组不显示任务开始对话框
        isControlGroup = await ExperimentConfigService.instance.isControlGroup(currentUser.uid);
        // if (isControlGroup) {
        //   // 对照组用户：记录通知结果为已查看，但不显示对话框（僅針對被點擊的通知）
        //   if (notifToRecord != null) {
        //     await ExperimentEventHelper.recordNotificationResult(
        //       uid: currentUser.uid,
        //       eventId: event.id,
        //       notifId: notifToRecord,
        //       result: NotificationResult.dismiss, // 标记为已查看但未采取行动
        //       eventDate: event.date, // 🎯 传递事件发生的日期
        //     );
        //   }
        //   return;
        // }
      }

      // 顯示任務開始彈窗（实验组和对照组都显示）
      // 在release mode中添加延迟以确保应用完全启动
      await Future.delayed(const Duration(milliseconds: 300));
      await _showTaskStartDialog(event, forceShow: forceShow, notifId: clickedNotifId, isControlGroup: isControlGroup);

    } catch (e) {
      if (kDebugMode) {
        print('處理通知點擊時發生錯誤: $e');
      }
      // 在release mode中，即使出错也尝试显示对话框
      try {
        if (payload != 'daily_report') {
          final event = await _getEventById(parsedEventId ?? payload);
          if (event != null && !event.isDone && event.actualStartTime == null) {
            // 🎯 特殊處理：test 任務不顯示 task start dialog
            if (event.title.toLowerCase().contains('test')) {
              if (kDebugMode) {
                print('🎯 release mode: test 任務不顯示 task start dialog: ${event.title}');
              }
              return;
            }
            await Future.delayed(const Duration(milliseconds: 500));
            await _showTaskStartDialog(event, forceShow: forceShow, notifId: clickedNotifId, isControlGroup: false);
          }
        }
      } catch (retryError) {
        if (kDebugMode) {
          print('重试顯示任務開始彈窗失敗: $retryError');
        }
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

      final doc = await DataPathService.instance.getEventDocAuto(currentUser.uid, eventId).then((ref) => ref.get());

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
  Future<void> _showTaskStartDialog(EventModel event, {bool forceShow = false, String? notifId, bool? isControlGroup}) async {
    // 🎯 最後防護：test 任務絕對不顯示 task start dialog
    if (event.title.toLowerCase().contains('test')) {
      if (kDebugMode) {
        print('🎯 _showTaskStartDialog: test 任務絕對不顯示 dialog: ${event.title}');
      }
      return;
    }
    
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
      // 在release mode中，如果context不可用，延迟重试
      await Future.delayed(const Duration(milliseconds: 500));
      final retryContext = NavigationService.context;
      if (retryContext == null) {
        if (kDebugMode) {
          print('重试后仍無法獲取 NavigationService 的 context');
        }
        return;
      }
    }

    // 检查用户分组（如果沒有傳入，則重新計算）
    bool controlGroup = false;
    if (isControlGroup != null) {
      controlGroup = isControlGroup;
    } else {
      final uid = AuthService.instance.currentUser?.uid;
      if (uid != null) {
        controlGroup = await ExperimentConfigService.instance.isControlGroup(uid);
      }
    }

    if (kDebugMode) {
      print('顯示任務開始彈窗: ${event.title}, isControlGroup: $controlGroup');
    }

    // 設置對話框顯示狀態
    setTaskStartDialogShowing(true);
    
    // 🎯 新增：設置通知觸發的 dialog 顯示狀態
    setNotificationTriggeredDialogShowing(true);
    
    // 🎯 新增：記錄通知觸發時間
    _lastNotificationTriggerTime = DateTime.now();
    if (kDebugMode) {
      print('🎯 記錄通知觸發時間: ${_lastNotificationTriggerTime}');
    }

    // 確保在主線程中執行，并添加延迟以确保UI完全加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        final currentContext = NavigationService.context;
        if (currentContext != null && currentContext.mounted) {
          showDialog(
            context: currentContext,
            barrierDismissible: false,
            builder: (context) {
              // 🎯 調試：確認傳遞給 TaskStartDialog 的事件
              if (kDebugMode) {
                print('🎯 Creating TaskStartDialog with:');
                print('🎯 Event ID: ${event.id}');
                print('🎯 Event Title: ${event.title}');
                print('🎯 NotifId: $notifId');
                print('🎯 IsControlGroup: $controlGroup');
              }
              return TaskStartDialog(
                event: event,
                notifId: notifId,
                isControlGroup: controlGroup,
                triggerSource: TaskStartDialogTrigger.notification, // 🎯 來自通知點擊
              );
            },
          ).then((_) {
            // 對話框關閉時重置狀態
            setTaskStartDialogShowing(false);
            setNotificationTriggeredDialogShowing(false); // 关闭通知触发状态
          }).catchError((error) {
            // 处理对话框显示错误
            if (kDebugMode) {
              print('顯示任務開始彈窗時發生錯誤: $error');
            }
            setTaskStartDialogShowing(false);
            setNotificationTriggeredDialogShowing(false); // 关闭通知触发状态
          });
        } else {
          // 如果context不可用，重置狀態
          if (kDebugMode) {
            print('延遲后仍無法獲取有效的 context');
          }
          setTaskStartDialogShowing(false);
          setNotificationTriggeredDialogShowing(false); // 关闭通知触发状态
        }
      });
    });
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

  // 🎯 已移除：任務完成提醒通知相關方法
  // 不再需要，因為已移除該功能
} 