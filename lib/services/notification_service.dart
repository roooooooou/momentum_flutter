import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';
import '../services/auth_service.dart';

// 通知偏移時間常數（開始前10分鐘）
const int notifOffsetMin = -10;

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

  /// 顯示簡單通知
  Future<bool> showNotification({
    required String title,
    required String body,
    String? payload,
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
      
      await _plugin.show(
        notificationId,
        title,
        body,
        details,
        payload: payload,
      );

      if (kDebugMode) {
        print('通知已發送: ID=$notificationId, 標題=$title');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('發送通知時發生錯誤: $e');
      }
      return false;
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

  /// 強制請求通知權限
  Future<bool> requestNotificationPermissions() async {
    final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (iosImplementation != null) {
      final granted = await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: false,
      );
      
      if (kDebugMode) {
        print('iOS 權限請求結果: $granted');
      }
      
      return granted == true;
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

  /// 排程事件通知
  Future<bool> scheduleEventNotification({
    required int notificationId,
    required String title,
    required DateTime eventStartTime,
    String? payload,
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

      // 計算觸發時間（事件開始前10分鐘）
      final triggerTime = eventStartTime.add(Duration(minutes: notifOffsetMin));
      
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

      // 轉換為時區時間
      final scheduledDate = tz.TZDateTime.from(triggerTime, tz.local);
      
      await _plugin.zonedSchedule(
        notificationId,
        '任務提醒',
        '您的任務「$title」即將開始',
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      if (kDebugMode) {
        print('事件通知已排程: ID=$notificationId, 標題=$title, 觸發時間=$triggerTime');
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
  Future<void> cancelEventNotification(String eventId, int? notifId) async {
    if (notifId != null) {
      await NotificationService.instance.cancelNotification(notifId);
      if (kDebugMode) {
        print('取消已刪除事件的通知: eventId=$eventId, notifId=$notifId');
      }
    }
  }

  /// 處理單個事件的通知排程
  Future<void> _processEvent(EventModel event, DateTime now) async {
    // 1. 事件已開始或已完成 → 取消通知
    if (event.startTime.isBefore(now) || event.isDone) {
      if (event.notifId != null) {
        await NotificationService.instance.cancelNotification(event.notifId!);
        // 清空通知資訊
        await _updateEventNotificationInfo(event.id, null, null);
        if (kDebugMode) {
          print('取消已開始/已完成事件的通知: ${event.title}');
        }
      }
      return;
    }

    // 2. 事件未排程通知 → 新增排程
    if (event.notifId == null) {
      final notificationId = _generateNotificationId(event.id);
      final success = await NotificationService.instance.scheduleEventNotification(
        notificationId: notificationId,
        title: event.title,
        eventStartTime: event.startTime,
        payload: event.id,
      );
      
      if (success) {
        // 更新事件的通知資訊（這裡需要回寫到 Firestore）
        await _updateEventNotificationInfo(event.id, notificationId, now);
        if (kDebugMode) {
          print('新增事件通知排程: ${event.title}');
        }
      }
      return;
    }

    // 3. 事件已修改 → 檢查是否需要重新排程
    if (event.updatedAt != null && 
        event.notifScheduledAt != null && 
        event.updatedAt!.isAfter(event.notifScheduledAt!)) {
      
      // 取消舊通知
      await NotificationService.instance.cancelNotification(event.notifId!);
      
      // 計算新的觸發時間
      final newTriggerTime = event.startTime.add(Duration(minutes: notifOffsetMin));
      
      // 檢查新觸發時間是否在過去
      if (newTriggerTime.isBefore(now)) {
        if (kDebugMode) {
          print('事件修改後觸發時間已過期，只取消舊通知: ${event.title}');
        }
        // 只取消舊通知，不排程新通知
        await _updateEventNotificationInfo(event.id, null, null);
        return;
      }
      
      // 排程新通知
      final success = await NotificationService.instance.scheduleEventNotification(
        notificationId: event.notifId!,
        title: event.title,
        eventStartTime: event.startTime,
        payload: event.id,
      );
      
      if (success) {
        await _updateEventNotificationInfo(event.id, event.notifId, now);
        if (kDebugMode) {
          print('重新排程已修改事件的通知: ${event.title}');
        }
      }
      return;
    }

    // 4. 其他情況 → 不動作
    if (kDebugMode) {
      print('事件無需處理通知: ${event.title}');
    }
  }

  /// 生成通知 ID
  int _generateNotificationId(String eventId) {
    return eventId.hashCode.abs();
  }

  /// 更新事件的通知資訊到 Firestore
  Future<void> _updateEventNotificationInfo(String eventId, int? notifId, DateTime? scheduledAt) async {
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

      await doc.update(updateData);
      
      if (kDebugMode) {
        print('更新事件通知資訊: eventId=$eventId, notifId=$notifId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('更新事件通知資訊失敗: $e');
      }
    }
  }
} 