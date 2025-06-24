import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';
import '../services/auth_service.dart';

// 通知偏移時間常數
const int firstNotifOffsetMin = -10;  // 第一個通知：開始前10分鐘
const int secondNotifOffsetMin = 5;   // 第二個通知：開始後5分鐘

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
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
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

  /// 處理通知點擊事件
  static void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      print('Notification tapped: ${response.payload}');
    }
  }

  /// 測試通知功能 (5秒後發送)
  Future<bool> showTestNotification() async {
    if (kDebugMode) {
      print('排程測試通知，將於5秒後發送...');
    }
    
    final success = await showScheduledNotification(
      title: '測試通知',
      body: '這是一個測試通知，您的 Local Notification 功能運作正常！',
      payload: 'test_notification',
      delaySeconds: 5,
    );
    
    if (kDebugMode) {
      print('測試通知排程結果: ${success ? "成功，5秒後將顯示" : "失敗"}');
    }
    
    return success;
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
      
      if (isSecondNotification) {
        notificationTitle = '任務提醒';
        notificationBody = '您的任務「$title」應該已經開始了，請檢查並開始執行！';
      } else {
        notificationTitle = '任務提醒';
        notificationBody = '您的任務「$title」即將開始';
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
        payload: payload,
      );

      if (kDebugMode) {
        print('事件通知已排程: ID=$notificationId, 標題=$title, 觸發時間=$triggerTime, 類型=${isSecondNotification ? "第二個" : "第一個"}');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('排程事件通知時發生錯誤: $e');
      }
      return false;
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
  Future<void> cancelEventNotification(String eventId, int? notifId, int? secondNotifId) async {
    if (notifId != null) {
      await NotificationService.instance.cancelNotification(notifId);
      if (kDebugMode) {
        print('取消已刪除事件的第一個通知: eventId=$eventId, notifId=$notifId');
      }
    }
    
    if (secondNotifId != null) {
      await NotificationService.instance.cancelNotification(secondNotifId);
      if (kDebugMode) {
        print('取消已刪除事件的第二個通知: eventId=$eventId, secondNotifId=$secondNotifId');
      }
    }
  }

  /// 當任務開始時取消第二個通知
  Future<void> cancelSecondNotification(String eventId, int? secondNotifId) async {
    if (secondNotifId != null) {
      await NotificationService.instance.cancelNotification(secondNotifId);
      // 清空第二個通知資訊
      await _updateEventSecondNotificationInfo(eventId, null, null);
      if (kDebugMode) {
        print('任務已開始，取消第二個通知: eventId=$eventId, secondNotifId=$secondNotifId');
      }
    }
  }

  /// 處理單個事件的通知排程
  Future<void> _processEvent(EventModel event, DateTime now) async {
    // 1. 事件已開始或已完成 → 取消所有通知
    if (event.isDone || event.actualStartTime != null) {
      if (event.notifId != null) {
        await NotificationService.instance.cancelNotification(event.notifId!);
      }
      if (event.secondNotifId != null) {
        await NotificationService.instance.cancelNotification(event.secondNotifId!);
      }
      // 清空所有通知資訊
      await _updateEventNotificationInfo(event.id, null, null, null, null);
      if (kDebugMode) {
        print('取消已開始/已完成事件的所有通知: ${event.title}');
      }
      return;
    }

    // 2. 事件未排程通知 → 新增雙重排程
    if (event.notifId == null && event.secondNotifId == null) {
      final firstNotificationId = _generateFirstNotificationId(event.id);
      final secondNotificationId = _generateSecondNotificationId(event.id);
      
      // 排程第一個通知
      final firstSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: firstNotificationId,
        title: event.title,
        eventStartTime: event.startTime,
        offsetMinutes: firstNotifOffsetMin,
        payload: event.id,
        isSecondNotification: false,
      );
      
      // 排程第二個通知
      final secondSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: secondNotificationId,
        title: event.title,
        eventStartTime: event.startTime,
        offsetMinutes: secondNotifOffsetMin,
        payload: event.id,
        isSecondNotification: true,
      );
      
      if (firstSuccess || secondSuccess) {
        // 更新事件的通知資訊
        await _updateEventNotificationInfo(
          event.id, 
          firstSuccess ? firstNotificationId : null, 
          firstSuccess ? now : null,
          secondSuccess ? secondNotificationId : null,
          secondSuccess ? now : null,
        );
        if (kDebugMode) {
          print('新增事件雙重通知排程: ${event.title}');
        }
      }
      return;
    }

    // 3. 事件已修改 → 檢查是否需要重新排程
    if (event.updatedAt != null && 
        (event.notifScheduledAt != null || event.secondNotifScheduledAt != null) && 
        event.updatedAt!.isAfter(event.notifScheduledAt ?? DateTime(1900)) &&
        event.updatedAt!.isAfter(event.secondNotifScheduledAt ?? DateTime(1900))) {
      
      // 取消舊通知
      if (event.notifId != null) {
        await NotificationService.instance.cancelNotification(event.notifId!);
      }
      if (event.secondNotifId != null) {
        await NotificationService.instance.cancelNotification(event.secondNotifId!);
      }
      
      // 重新排程通知
      final firstNotificationId = event.notifId ?? _generateFirstNotificationId(event.id);
      final secondNotificationId = event.secondNotifId ?? _generateSecondNotificationId(event.id);
      
      final firstSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: firstNotificationId,
        title: event.title,
        eventStartTime: event.startTime,
        offsetMinutes: firstNotifOffsetMin,
        payload: event.id,
        isSecondNotification: false,
      );
      
      final secondSuccess = await NotificationService.instance.scheduleEventNotification(
        notificationId: secondNotificationId,
        title: event.title,
        eventStartTime: event.startTime,
        offsetMinutes: secondNotifOffsetMin,
        payload: event.id,
        isSecondNotification: true,
      );
      
      if (firstSuccess || secondSuccess) {
        await _updateEventNotificationInfo(
          event.id, 
          firstSuccess ? firstNotificationId : null, 
          firstSuccess ? now : null,
          secondSuccess ? secondNotificationId : null,
          secondSuccess ? now : null,
        );
        if (kDebugMode) {
          print('重新排程已修改事件的雙重通知: ${event.title}');
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

  /// 更新事件的通知資訊到 Firestore
  Future<void> _updateEventNotificationInfo(
    String eventId, 
    int? notifId, 
    DateTime? scheduledAt,
    int? secondNotifId,
    DateTime? secondScheduledAt,
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

      final updateData = <String, dynamic>{};
      
      // 更新第一個通知資訊
      if (notifId != null) {
        updateData['notifId'] = notifId;
      } else {
        updateData['notifId'] = null;
      }
      
      if (scheduledAt != null) {
        updateData['notifScheduledAt'] = Timestamp.fromDate(scheduledAt);
      } else {
        updateData['notifScheduledAt'] = null;
      }
      
      // 更新第二個通知資訊
      if (secondNotifId != null) {
        updateData['secondNotifId'] = secondNotifId;
      } else {
        updateData['secondNotifId'] = null;
      }
      
      if (secondScheduledAt != null) {
        updateData['secondNotifScheduledAt'] = Timestamp.fromDate(secondScheduledAt);
      } else {
        updateData['secondNotifScheduledAt'] = null;
      }

      await doc.update(updateData);
      
      if (kDebugMode) {
        print('更新事件通知資訊: eventId=$eventId, notifId=$notifId, secondNotifId=$secondNotifId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('更新事件通知資訊失敗: $e');
      }
    }
  }

  /// 更新事件的第二個通知資訊到 Firestore
  Future<void> _updateEventSecondNotificationInfo(
    String eventId,
    int? secondNotifId,
    DateTime? secondScheduledAt,
  ) async {
    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          print('無法獲取當前用戶，跳過更新第二個通知資訊');
        }
        return;
      }
      
      final uid = currentUser.uid;
      
      final doc = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .doc(eventId);

      final updateData = <String, dynamic>{};
      
      if (secondNotifId != null) {
        updateData['secondNotifId'] = secondNotifId;
      } else {
        updateData['secondNotifId'] = null;
      }
      
      if (secondScheduledAt != null) {
        updateData['secondNotifScheduledAt'] = Timestamp.fromDate(secondScheduledAt);
      } else {
        updateData['secondNotifScheduledAt'] = null;
      }

      await doc.update(updateData);
      
      if (kDebugMode) {
        print('更新事件第二個通知資訊: eventId=$eventId, secondNotifId=$secondNotifId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('更新事件第二個通知資訊失敗: $e');
      }
    }
  }
} 