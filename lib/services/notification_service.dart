import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/auth_service.dart';
import '../services/notification_handler.dart';
import '../services/data_path_service.dart';
import '../services/experiment_config_service.dart';

// 通知偏移時間常數
const int firstNotifOffsetMin = -10;  // 第一個通知：開始前10分鐘
const int secondNotifOffsetMin = 0;   // 第二個通知：開始後5分鐘

// 通知ID範圍常數
const int EVENT_NOTIFICATION_ID_BASE = 1000;      // 事件通知基礎ID
const int DAILY_REPORT_NOTIFICATION_ID = 999999;  // 每日報告通知ID
const int TASK_COMPLETION_ID_BASE = 2000;         // 任務完成提醒基礎ID

// ⬇️ iOS terminated 時的 top-level 函式
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse resp) {
  _handleTap(resp.payload);
}

// ⬇️ 統一的通知點擊處理函式
void _handleTap(String? payload) {
  if (kDebugMode) {
    print('通知被點擊，payload: $payload');
  }
  
  // 使用 NotificationHandler 處理點擊事件
  NotificationHandler.instance.handleNotificationTap(payload);
}

// ⬇️ 通知發送處理函式
void _handleNotificationDelivered(NotificationResponse notification) {
  if (kDebugMode) {
    print('通知已發送: ${notification.payload}');
  }
  
  // 記錄通知發送時間
  if (notification.payload != null) {
    NotificationService.instance.recordNotificationDelivered(notification.payload!);
  }
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = 
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 初始化通知服務 (iOS)
  Future<void> initialize() async {
    if (_initialized) return;

    // 初始化時區數據
    tz.initializeTimeZones();

    // iOS 設定
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      // 套件預設已經全開，但明確設定確保行為一致
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,

      notificationCategories: [
        DarwinNotificationCategory(
            'momentum_notification',
            actions: [
                DarwinNotificationAction.plain('start_now', '準備開始了！'),
                DarwinNotificationAction.plain('snooze', '現在還不想做'),
            ],
            ),
        ],
    );

    final initSettings = InitializationSettings(
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) => _handleTap(response.payload),
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    

    // 請求權限
    final permissionsGranted = await _requestPermissions();
    
    if (!permissionsGranted) {
      if (kDebugMode) {
        print('通知權限被拒絕');
      }
      return; // 如果權限被拒絕，不初始化
    }

    _initialized = true;
    if (kDebugMode) {
      print('NotificationService initialized');
    }
  }

  /// 請求通知權限 (iOS)
  Future<bool> _requestPermissions() async {
    // iOS 權限請求
    final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (iosImplementation != null) {
      final iosPermission = await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: false,
      );
      if (kDebugMode) {
        print('iOS 通知權限: $iosPermission');
      }
      return iosPermission == true;
    }

    // 非 iOS 平台，返回 false
    return false;
  }





  /// 顯示定時通知
  Future<bool> showScheduledNotification({
    required String title,
    required String body,
    String? payload,
    required int delaySeconds,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      if (!_initialized) {
        if (kDebugMode) {
          print('通知服務初始化失敗');
        }
        return false;
      }

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        categoryIdentifier: 'momentum_notification',
        threadIdentifier: 'momentum_thread',
        interruptionLevel: InterruptionLevel.active,
        // 關鍵設置：讓前台也顯示通知
        presentBanner: true,
        presentList: true,
      );

      const details = NotificationDetails(
        iOS: iosDetails,
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      final scheduledDate = tz.TZDateTime.now(tz.local).add(Duration(seconds: delaySeconds));
      
      await _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      if (kDebugMode) {
        print('通知已排程: ID=$notificationId, 標題=$title, 將於$delaySeconds秒後顯示');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('排程通知時發生錯誤: $e');
      }
      return false;
    }
  }

  /// 檢查通知權限狀態 (iOS)
  Future<bool> areNotificationsEnabled() async {
    final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (iosImplementation != null) {
      final settings = await iosImplementation.checkPermissions();
      if (kDebugMode) {
        print('iOS 通知權限狀態: $settings');
      }
      return settings?.isEnabled ?? false;
    }
    
    return false;
  }

  /// 取消指定 ID 的通知
  Future<void> cancelNotification(int id) async {
    try {
      await _plugin.cancel(id);
      if (kDebugMode) {
        print('通知已取消: ID=$id');
      }
    } catch (e) {
      if (kDebugMode) {
        print('取消通知時發生錯誤: $e');
      }
    }
  }

  /// 取消用户的所有通知（用于组别切换时）
  Future<void> cancelAllUserNotifications(String uid) async {
    try {
      if (kDebugMode) {
        print('开始取消用户 $uid 的所有通知...');
      }

      // 获取用户今天的所有事件
      final now = DateTime.now();
      final localToday = DateTime(now.year, now.month, now.day);
      final localTomorrow = localToday.add(const Duration(days: 1));
      final start = localToday.toUtc();
      final end = localTomorrow.toUtc();

      // 获取用户的事件集合（使用DataPathService确保路径正确）
      final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
      
      final snap = await eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .get();

      final events = snap.docs.map(EventModel.fromDoc).toList();
      
      int cancelledCount = 0;
      
      // 取消每个事件的所有通知
      for (final event in events) {
        if (event.notifIds.isNotEmpty) {
          // 取消第一个通知
          final firstNotificationId = event.id.hashCode.abs();
          await cancelNotification(firstNotificationId);
          
          // 取消第二个通知
          final secondNotificationId = -(event.id.hashCode.abs());
          await cancelNotification(secondNotificationId);
          
          // 取消任务完成提醒通知
          final completionNotificationId = TASK_COMPLETION_ID_BASE + (event.id.hashCode.abs() % 100000);
          await cancelNotification(completionNotificationId);
          
          cancelledCount++;
          
          if (kDebugMode) {
            print('已取消事件 ${event.title} 的所有通知');
          }
        }
      }

      // 不取消每日报告通知
      if (kDebugMode) {
        print('组别切换：成功取消用户 $uid 的 $cancelledCount 个事件的通知，保留每日报告通知');
      }
    } catch (e) {
      if (kDebugMode) {
        print('取消用户所有通知时发生错误: $e');
      }
    }
  }

  /// 排程事件通知（支持偏移時間）
  Future<bool> scheduleEventNotification({
    required int notificationId,
    required String title,
    required DateTime eventStartTime,
    required int offsetMinutes,
    String? payload,
    bool isSecondNotification = false,
    String? customTitle, // 新增：自定义标题
    String? customBody,  // 新增：自定义内容
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      if (!_initialized) {
        if (kDebugMode) {
          print('通知服務初始化失敗');
        }
        return false;
      }

      // 計算觸發時間
      final triggerTime = eventStartTime.add(Duration(minutes: offsetMinutes));
      
      // 檢查觸發時間是否在過去
      if (triggerTime.isBefore(DateTime.now())) {
        if (kDebugMode) {
          print('觸發時間已過期，不排程通知: $triggerTime');
        }
        return false;
      }

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        categoryIdentifier: 'momentum_notification',
        threadIdentifier: 'momentum_thread',
        interruptionLevel: InterruptionLevel.active,
        presentBanner: true,
        presentList: true,
      );

      const details = NotificationDetails(
        iOS: iosDetails,
      );

      // 根據通知類型和用户组設置不同的內容
      String notificationTitle;
      String notificationBody;
      
      if (customTitle != null && customBody != null) {
        // 使用自定义标题和内容（用于任务完成提醒）
        notificationTitle = customTitle;
        notificationBody = customBody;
      } else {
      // 根據事件發生的日期檢查用戶組別以決定通知內容（W1/W2 + manual A/B）
        final currentUser = AuthService.instance.currentUser;
        bool isControlGroup = false;
        
        if (currentUser != null) {
          try {
            // 使用事件发生的日期来确定组别，而不是当前日期
            final eventDate = eventStartTime.toLocal();
            final groupName = await ExperimentConfigService.instance.getDateGroup(currentUser.uid, eventDate);
            isControlGroup = groupName == 'control';
            
            if (kDebugMode) {
              print('🎯 事件日期 ${eventDate.toString().substring(0, 10)} 的组别: $groupName');
            }
          } catch (e) {
            if (kDebugMode) {
              print('检查用户分组失败，使用默认实验组通知: $e');
            }
          }
        }
        
        if (isSecondNotification) {
          notificationTitle = '現在開始剛剛好';
          if (isControlGroup) {
            // 对照组：不提及聊天功能
            notificationBody = '你已經開始任務「$title」了嗎？現在開始剛剛好！';
          } else {
            // 实验组：保持原有文本
            notificationBody = '你已經開始任務「$title」了嗎？還沒有想法的話，需要跟我聊聊嗎？';
          }
        } else {
          notificationTitle = '事件即將開始';
          if (isControlGroup) {
            // 对照组：不提及聊天功能
            notificationBody = '任務「$title」即將開始，準備好開始了嗎？';
          } else {
            // 实验组：保持原有文本
            notificationBody = '準備好開始任務「$title」了嗎？還不想開始的話，需要跟我聊聊嗎？';
          }
        }
        
        if (kDebugMode) {
          print('通知内容设置: 用户组=${isControlGroup ? "对照组" : "实验组"}, 标题="$notificationTitle", 内容="$notificationBody"');
        }
      }

      // 轉換為時區時間
      final scheduledDate = tz.TZDateTime.from(triggerTime, tz.local);
      
      await _plugin.zonedSchedule(
        notificationId,
        notificationTitle,
        notificationBody,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload, // 使用事件ID作為 payload
      );

      // 🎯 實驗數據收集：記錄通知發送成功
      if (payload != null) {
        final currentUser = AuthService.instance.currentUser;
        if (currentUser != null) {
          String? notifId;
          String? eventId;
          
          if (payload.startsWith('task_completion_')) {
            // 完成提醒通知
            eventId = payload.replaceFirst('task_completion_', '');
            notifId = '$eventId-complete';
          } else if (customTitle == null) {
            // 普通事件通知（开始前通知）
            eventId = payload;
            notifId = isSecondNotification ? '$payload-2nd' : '$payload-1st';
          }
          // 其他自定义通知不记录
          
          if (notifId != null && eventId != null) {
            final eventDate = eventStartTime.toLocal(); // 🎯 获取事件发生的日期
            
            // 🎯 修复：记录通知排程信息，但不记录delivered_time
            await ExperimentEventHelper.recordNotificationScheduled(
              uid: currentUser.uid,
              eventId: eventId,
              notifId: notifId,
              scheduledTime: triggerTime, // 傳遞實際排程時間（通知應該觸發的時間）
              eventDate: eventDate, // 🎯 傳遞事件发生的日期
            );
          }
        }
      }

      if (kDebugMode) {
        print('事件通知已排程: ID=$notificationId, 標題=$title, 觸發時間=$triggerTime, 類型=${customTitle != null ? "自定義" : (isSecondNotification ? "第二個" : "第一個")}');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('排程事件通知時發生錯誤: $e');
      }
      return false;
    }
  }

  /// 安排每日报告通知（每天晚上10点）
  Future<bool> scheduleDailyReportNotification() async {
    try {
      if (!_initialized) {
        await initialize();
      }

      if (!_initialized) {
        if (kDebugMode) {
          print('通知服務初始化失敗');
        }
        return false;
      }

      // 計算今天晚上10點的時間
      final now = DateTime.now();
      var today10PM = DateTime(now.year, now.month, now.day, 22, 0); // 晚上10點

      // 如果已經過了今天的10點，則安排明天的10點
      if (today10PM.isBefore(now)) {
        today10PM = today10PM.add(const Duration(days: 1));
        
        // 如果要調度到明天，需要檢查明天是否有任務
        final hasTomorrowTasks = await _checkIfHasTasks(today10PM);
        if (!hasTomorrowTasks) {
          if (kDebugMode) {
            print('明日沒有任務安排，不需要調度每日報告通知到明天');
          }
          //await cancelDailyReportNotification();
          return true;
        }
      }

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        categoryIdentifier: 'daily_report_notification',
        threadIdentifier: 'daily_report_thread',
        interruptionLevel: InterruptionLevel.active,
        presentBanner: true,
        presentList: true,
      );

      const details = NotificationDetails(
        iOS: iosDetails,
      );

      // 轉換為時區時間
      final scheduledDate = tz.TZDateTime.from(today10PM, tz.local);
      
      await _plugin.zonedSchedule(
        DAILY_REPORT_NOTIFICATION_ID, // 使用固定的ID給每日報告通知
        '📋 今日任務總結',
        '今天過得如何？來填寫每日報告，記錄今日的任務完成情況吧！',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'daily_report', // 特殊的payload標識
      );

      if (kDebugMode) {
        print('每日報告通知已排程: 觸發時間=$today10PM');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('排程每日報告通知時發生錯誤: $e');
      }
      return false;
    }
  }

  /// 🎯 新增：为指定日期排定daily report通知
  Future<bool> scheduleDailyReportNotificationForDate(DateTime targetDate, int notificationId) async {
    try {
      if (!_initialized) {
        await initialize();
      }

      if (!_initialized) {
        if (kDebugMode) {
          print('通知服務初始化失敗');
        }
        return false;
      }

      // 计算目标日期的晚上10点
      final targetTime = DateTime(targetDate.year, targetDate.month, targetDate.day, 22, 0);
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        categoryIdentifier: 'daily_report_notification',
        threadIdentifier: 'daily_report_thread',
        interruptionLevel: InterruptionLevel.active,
        presentBanner: true,
        presentList: true,
      );

      const details = NotificationDetails(
        iOS: iosDetails,
      );

      // 转换為時區時間
      final scheduledDate = tz.TZDateTime.from(targetTime, tz.local);
      final nowTz = tz.TZDateTime.now(tz.local);
      // 若時間已過，直接略過，避免拋錯
      if (!scheduledDate.isAfter(nowTz)) {
        if (kDebugMode) {
          print('跳過已過去的每日報告通知: ${scheduledDate.toString()}');
        }
        return false;
      }
      
      await _plugin.zonedSchedule(
        notificationId,
        '📋 今日任務總結',
        '今天過得如何？來填寫每日報告，記錄今日的任務完成情況吧！',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'daily_report_${targetDate.year}${targetDate.month.toString().padLeft(2, '0')}${targetDate.day.toString().padLeft(2, '0')}',
      );
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('🎯 排定单日通知失败: $e');
      }
      return false;
    }
  }

  /// 檢查今日是否有任務安排
  Future<bool> _checkIfHasTasksToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return await _checkIfHasTasks(today);
  }

  /// 檢查指定日期是否有任務安排
  Future<bool> _checkIfHasTasks(DateTime date) async {
    try {
      final uid = AuthService.instance.currentUser?.uid;
      if (uid == null) {
        if (kDebugMode) {
          print('用戶未登錄，無法檢查任務');
        }
        return false;
      }

      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      if (kDebugMode) {
        print('檢查任務範圍: ${startOfDay.toUtc()} 到 ${endOfDay.toUtc()}');
      }

      // 🎯 依日期選擇 w1/w2 事件集合
      final eventsCol = await DataPathService.instance.getDateEventsCollection(uid, date);

      final snapshot = await eventsCol
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay.toUtc()))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(endOfDay.toUtc()))
          .get(); // 移除limit(1)，获取所有事件进行详细检查

      if (kDebugMode) {
        print('找到 ${snapshot.docs.length} 个事件');
      }

      // 檢查是否有事件
      bool hasTasks = false;
      int taskCount = 0;

      for (final doc in snapshot.docs) {
        final eventData = doc.data() as Map<String, dynamic>;
        final title = eventData['title'] as String? ?? 'Unknown';
        
        // 简化逻辑：只要找到事件就算有任务
        taskCount++;
        hasTasks = true;
        if (kDebugMode) {
          print('✅ 找到事件: $title');
        }
      }

      if (kDebugMode) {
        print('檢查日期 ${date.toString().substring(0, 10)} 是否有任務: $hasTasks (事件数量: $taskCount)');
      }

      return hasTasks;
    } catch (e) {
      if (kDebugMode) {
        print('檢查任務時發生錯誤: $e');
      }
      // 發生錯誤時，為了安全起見，假設有任務（這樣不會錯過重要通知）
      return true;
    }
  }

  /// 取消每日报告通知
  Future<void> cancelDailyReportNotification() async {
    try {
      await _plugin.cancel(DAILY_REPORT_NOTIFICATION_ID);
      if (kDebugMode) {
        print('每日報告通知已取消');
      }
    } catch (e) {
      if (kDebugMode) {
        print('取消每日報告通知時發生錯誤: $e');
      }
    }
  }

  /// 测试每日报告通知检查（用于调试）
  Future<void> testDailyReportCheck() async {
    if (kDebugMode) {
      print('=== 开始测试每日报告通知检查 ===');
      final hasTasksToday = await _checkIfHasTasksToday();
      print('今日是否有任务: $hasTasksToday');
      print('=== 测试完成 ===');
    }
  }

  /// 記錄通知發送時間
  Future<void> recordNotificationDelivered(String payload) async {
    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) return;

      String? notifId;
      String? eventId;
      
      if (payload.startsWith('task_completion_')) {
        // 完成提醒通知
        eventId = payload.replaceFirst('task_completion_', '');
        notifId = '$eventId-complete';
      } else {
        // 普通事件通知（开始前通知）
        eventId = payload;
        notifId = payload; // 使用payload作为notifId
      }
      
      if (notifId != null && eventId != null) {
        // 获取事件信息来确定事件发生的日期
        final eventDoc = await DataPathService.instance.getEventDocAuto(currentUser.uid, eventId);
        final eventSnap = await eventDoc.get();
        
        if (eventSnap.exists) {
          final eventData = eventSnap.data() as Map<String, dynamic>?;
          if (eventData != null) {
            final eventDate = (eventData['date'] as Timestamp?)?.toDate();
            
            await ExperimentEventHelper.recordNotificationDelivered(
              uid: currentUser.uid,
              eventId: eventId,
              notifId: notifId,
              eventDate: eventDate,
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('記錄通知發送時間失敗: $e');
      }
    }
  }
}

/// 通知排程器
class NotificationScheduler {
  static final NotificationScheduler _instance = NotificationScheduler._internal();
  factory NotificationScheduler() => _instance;
  NotificationScheduler._internal();

  /// 同步事件列表的通知排程
  Future<void> sync(List<EventModel> events) async {
    final now = DateTime.now();
    
    for (final event in events) {
      await _processEvent(event, now);
    }
  }

  /// 取消指定事件的通知
  Future<void> cancelEventNotification(String eventId, List<String> notifIds) async {
    await _cancelEventNotifications(eventId, notifIds);
  }

  /// 當任務開始時取消第二個通知
  Future<void> cancelSecondNotification(String eventId) async {
    final secondNotificationId = _generateSecondNotificationId(eventId);
    await NotificationService.instance.cancelNotification(secondNotificationId);
    
    // 更新notifIds，移除第二個通知
    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        // 使用 DataPathService 获取正确的事件文档引用
        final doc = await DataPathService.instance.getEventDocAuto(currentUser.uid, eventId);
        
        await doc.update({
          'notifIds': ['${eventId}-1st'], // 只保留第一個通知
        });
      }
      
      if (kDebugMode) {
        print('任務已開始，取消第二個通知: eventId=$eventId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('更新通知ID列表失敗: $e');
      }
    }
  }

  /// 處理單個事件的通知排程
  Future<void> _processEvent(EventModel event, DateTime now) async {
    // 1. 事件已開始或已完成 → 取消所有通知
    if (event.isDone || event.actualStartTime != null) {
      // 取消現有的所有通知
      await _cancelEventNotifications(event.id, event.notifIds);
      // 清空通知資訊
      await _updateEventNotificationInfo(event.id, [], event.date);
      if (kDebugMode) {
        print('取消已開始/已完成事件的所有通知: ${event.title}');
      }
      return;
    }

    // 2. 事件未排程通知 → 新增雙重排程
    if (event.notifIds.isEmpty) {
      final firstNotificationId = _generateFirstNotificationId(event.id);
      final secondNotificationId = _generateSecondNotificationId(event.id);
      
      final notifIds = <String>[];
      
      // 排程第一個通知
      final firstSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: firstNotificationId,
        title: event.title,
        eventStartTime: event.scheduledStartTime,
        offsetMinutes: firstNotifOffsetMin,
        payload: event.id,
        isSecondNotification: false,
      );
      
      if (firstSuccess) {
        notifIds.add('${event.id}-1st');
      }
      
      // 排程第二個通知
      final secondSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: secondNotificationId,
        title: event.title,
        eventStartTime: event.scheduledStartTime,
        offsetMinutes: secondNotifOffsetMin,
        payload: event.id,
        isSecondNotification: true,
      );
      
      if (secondSuccess) {
        notifIds.add('${event.id}-2nd');
      }
      
      if (notifIds.isNotEmpty) {
        // 更新事件的通知資訊
        await _updateEventNotificationInfo(event.id, notifIds, event.date);
        if (kDebugMode) {
          print('新增事件雙重通知排程: ${event.title}, notifIds: $notifIds');
        }
      }
      return;
    }

    // 3. 事件已修改 → 檢查是否需要重新排程
    if (event.updatedAt != null && 
        event.notifScheduledAt != null && 
        event.updatedAt!.isAfter(event.notifScheduledAt!)) {
      
      // 取消現有通知
      await _cancelEventNotifications(event.id, event.notifIds);
      
      // 重新排程通知
      final firstNotificationId = _generateFirstNotificationId(event.id);
      final secondNotificationId = _generateSecondNotificationId(event.id);
      
      final notifIds = <String>[];
      
      final firstSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: firstNotificationId,
        title: event.title,
        eventStartTime: event.scheduledStartTime,
        offsetMinutes: firstNotifOffsetMin,
        payload: event.id,
        isSecondNotification: false,
      );
      
      if (firstSuccess) {
        notifIds.add('${event.id}-1st');
      }
      
      final secondSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: secondNotificationId,
        title: event.title,
        eventStartTime: event.scheduledStartTime,
        offsetMinutes: secondNotifOffsetMin,
        payload: event.id,
        isSecondNotification: true,
      );
      
      if (secondSuccess) {
        notifIds.add('${event.id}-2nd');
      }
      
      if (notifIds.isNotEmpty) {
        await _updateEventNotificationInfo(event.id, notifIds, event.date);
        if (kDebugMode) {
          print('重新排程已修改事件的雙重通知: ${event.title}, notifIds: $notifIds');
        }
      }
      return;
    }

    // 4. 其他情況 → 不動作
    if (kDebugMode) {
      print('事件無需處理通知: ${event.title}');
    }
  }

  /// 生成第一個通知 ID
  int _generateFirstNotificationId(String eventId) {
    // 使用事件ID的hashCode，但確保在安全範圍內
    final hash = eventId.hashCode.abs();
    return EVENT_NOTIFICATION_ID_BASE + (hash % 100000); // 確保ID在1000-101000範圍內
  }

  /// 生成第二個通知 ID
  int _generateSecondNotificationId(String eventId) {
    // 使用事件ID的hashCode，但確保在安全範圍內且為負數
    final hash = eventId.hashCode.abs();
    return -(EVENT_NOTIFICATION_ID_BASE + (hash % 100000)); // 確保ID在-1000到-101000範圍內
  }

  /// 取消事件的所有通知
  Future<void> _cancelEventNotifications(String eventId, List<String> notifIds) async {
    // 取消現有通知
    final firstNotificationId = _generateFirstNotificationId(eventId);
    final secondNotificationId = _generateSecondNotificationId(eventId);
    
    await NotificationService.instance.cancelNotification(firstNotificationId);
    await NotificationService.instance.cancelNotification(secondNotificationId);
    
    if (kDebugMode) {
      print('取消事件通知: eventId=$eventId, notifIds=$notifIds');
    }
  }

  /// 更新事件的通知資訊到 Firestore
  Future<void> _updateEventNotificationInfo(
    String eventId, 
    List<String> notifIds,
    DateTime? eventDate, // 🎯 新增：事件发生的日期
  ) async {
    try {
      // 從 AuthService 獲取當前用戶 ID
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('無法獲取當前用戶，跳過更新通知資訊');
        }
        return;
      }
      
      final uid = currentUser.uid;
      
      // 🎯 修复：根据事件发生的日期获取正确的事件文档引用
      DocumentReference doc;
      if (eventDate != null) {
        doc = await DataPathService.instance.getDateEventDoc(uid, eventId, eventDate);
      } else {
        doc = await DataPathService.instance.getUserEventDoc(uid, eventId);
      }

      final updateData = <String, dynamic>{
        'notifIds': notifIds,
        'notifScheduledAt': Timestamp.fromDate(DateTime.now()),
      };

      await doc.update(updateData);
      
      if (kDebugMode) {
        print('更新事件通知資訊: eventId=$eventId, notifIds=$notifIds, eventDate=$eventDate');
      }
    } catch (e) {
      if (kDebugMode) {
        print('更新事件通知資訊失敗: $e');
      }
    }
  }


} 