import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = 
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 初始化通知服務 (僅 iOS)
  Future<void> initialize() async {
    if (_initialized) return;

    // 初始化時區數據
    tz.initializeTimeZones();

    // iOS 設定
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
      defaultPresentBanner: true,  
      defaultPresentList: true,   

      notificationCategories: [
        DarwinNotificationCategory(
            'momentum_notification',
            actions: [
                DarwinNotificationAction.plain('start_now', '準備開始了！'),
                DarwinNotificationAction.plain('snooze', '現在還不想做'),
            ],
            ),
        ],

        onDidReceiveLocalNotification: onDidReceiveLocalNotification,
    );

    final initSettings = InitializationSettings(
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );

    // 為 iOS 設置前台通知顯示選項
    final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: false,
      );
    }

    // 請求權限（僅 iOS）
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

  /// 請求通知權限 (僅 iOS)
  Future<bool> _requestPermissions() async {
    // iOS 權限請求
    final iosImplementation = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    
    if (iosImplementation != null) {
      final iosPermission = await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
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

  /// 處理前台通知（iOS 舊版本兼容性）
  static void onDidReceiveLocalNotification(int id, String? title, String? body, String? payload) {
    if (kDebugMode) {
      print('前台通知接收: id=$id, title=$title, body=$body');
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
        payload: payload,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      if (kDebugMode) {
        print('通知已排程: ID=$notificationId, 標題=$title, 將於${delaySeconds}秒後顯示');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('排程通知時發生錯誤: $e');
      }
      return false;
    }
  }

  /// 檢查通知權限狀態 (僅 iOS)
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
        print('權限請求結果: $granted');
      }
      
      return granted == true;
    }
    
    return false;
  }
} 