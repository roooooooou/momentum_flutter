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
        notificationTitle = '現在開始剛剛好';
        notificationBody = '您的任務「$title」應該已經開始了，現在開始剛剛好！';
      } else {
        notificationTitle = '事件即將開始';
        notificationBody = '您的任務「$title」即將開始，準備好了嗎？';
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
          final notifId = isSecondNotification ? '$payload-2nd' : '$payload-1st';
          await ExperimentEventHelper.recordNotificationDelivered(
            uid: currentUser.uid,
            eventId: payload,
            notifId: notifId,
          );
        }
      }

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