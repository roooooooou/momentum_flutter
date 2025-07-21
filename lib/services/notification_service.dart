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

// 通知偏移時間常數
const int firstNotifOffsetMin = -10;  // 第一個通知：開始前10分鐘
const int secondNotifOffsetMin = 5;   // 第二個通知：開始後5分鐘

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

      // 根據通知類型設置不同的內容
      String notificationTitle;
      String notificationBody;
      
      if (customTitle != null && customBody != null) {
        // 使用自定义标题和内容（用于任务完成提醒）
        notificationTitle = customTitle;
        notificationBody = customBody;
      } else if (isSecondNotification) {
        notificationTitle = '現在開始剛剛好';
        notificationBody = '任務「$title」應該已經開始了，現在開始剛剛好！需要跟我聊聊嗎？';
      } else {
        notificationTitle = '事件即將開始';
        notificationBody = '任務「$title」即將開始，有開始的動力嗎？需要跟我聊聊嗎？';
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

      // 🎯 實驗數據收集：記錄通知發送成功（只针对普通事件通知，不包括自定义通知）
      if (payload != null && customTitle == null) {
        final currentUser = AuthService.instance.currentUser;
        if (currentUser != null) {
          final notifId = isSecondNotification ? '$payload-2nd' : '$payload-1st';
          final scheduleTime = DateTime.now(); // 記錄排程時間
          await ExperimentEventHelper.recordNotificationDelivered(
            uid: currentUser.uid,
            eventId: payload,
            notifId: notifId,
            scheduledTime: scheduleTime, // 傳遞排程時間
          );
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

      // 檢查今日是否有任務安排
      final hasTasksToday = await _checkIfHasTasksToday();
      if (!hasTasksToday) {
        if (kDebugMode) {
          print('今日沒有任務安排，不需要發送每日報告通知');
        }
        // 取消可能已經存在的通知
        await cancelDailyReportNotification();
        return true; // 返回true表示邏輯執行成功（雖然沒有調度通知）
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
          await cancelDailyReportNotification();
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
        999999, // 使用固定的ID給每日報告通知
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

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay.toUtc()))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(endOfDay.toUtc()))
          .limit(1) // 只需要檢查是否存在，不需要全部數據
          .get();

      // 檢查是否有活躍事件
      final hasActiveTasks = snapshot.docs.any((doc) {
        final eventData = doc.data();
        final lifecycleStatus = eventData['lifecycleStatus'];
        // 如果沒有lifecycleStatus字段（舊數據）或者是active狀態，都算作有任務
        return lifecycleStatus == null || lifecycleStatus == 0; // 0 = EventLifecycleStatus.active.value
      });

      if (kDebugMode) {
        print('檢查日期 ${date.toString().substring(0, 10)} 是否有任務: $hasActiveTasks (總事件數: ${snapshot.docs.length})');
      }

      return hasActiveTasks;
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
      await _plugin.cancel(999999);
      if (kDebugMode) {
        print('每日報告通知已取消');
      }
    } catch (e) {
      if (kDebugMode) {
        print('取消每日報告通知時發生錯誤: $e');
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
        final doc = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('events')
            .doc(eventId);
        
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
      await _updateEventNotificationInfo(event.id, []);
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
        await _updateEventNotificationInfo(event.id, notifIds);
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
        await _updateEventNotificationInfo(event.id, notifIds);
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
    return eventId.hashCode.abs();
  }

  /// 生成第二個通知 ID
  int _generateSecondNotificationId(String eventId) {
    return -(eventId.hashCode.abs()); // 使用負數避免衝突
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
      
      final doc = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .doc(eventId);

      final updateData = <String, dynamic>{
        'notifIds': notifIds,
        'notifScheduledAt': Timestamp.fromDate(DateTime.now()),
      };

      await doc.update(updateData);
      
      if (kDebugMode) {
        print('更新事件通知資訊: eventId=$eventId, notifIds=$notifIds');
      }
    } catch (e) {
      if (kDebugMode) {
        print('更新事件通知資訊失敗: $e');
      }
    }
  }


} 