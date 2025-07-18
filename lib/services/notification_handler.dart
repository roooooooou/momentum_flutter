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

class NotificationHandler {
  NotificationHandler._();
  static final instance = NotificationHandler._();

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
          barrierDismissible: false,
          builder: (context) => TaskStartDialog(event: event),
        );
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
} 