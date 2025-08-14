import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/event_model.dart';
import 'auth_service.dart';
import 'data_path_service.dart';
import 'notification_service.dart';

/// 監聽 Firestore 的 `users/{uid}.manual_week_assignment` 變更
/// 當分組切換（A/B）時，自動取消今天所有事件通知，並重新排程今天尚未開始的事件通知。
class GroupAssignmentWatcher {
  GroupAssignmentWatcher._();
  static final GroupAssignmentWatcher instance = GroupAssignmentWatcher._();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? _lastAssignment; // 'A' | 'B'
  String? _listeningUid;

  bool get isListening => _subscription != null;

  Future<void> start(String uid) async {
    if (_listeningUid == uid && _subscription != null) return;
    await stop();
    _listeningUid = uid;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    _subscription = userRef.snapshots().listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data();
      final current = (data?['manual_week_assignment'] as String?)?.trim(); // 'A' or 'B' or null

      // 第一次讀取只記錄，不觸發重排
      if (_lastAssignment == null) {
        _lastAssignment = current;
        return;
      }

      // 無變化則略過
      if (_lastAssignment == current) return;

      // 發生變更 → 取消並重排今天與未來的事件與每日報告通知
      _lastAssignment = current;
      try {
        if (kDebugMode) {
          print('manual_week_assignment 變更為: ${current ?? '(null)'}，重新排程今天起的通知');
        }

        // 1) 先處理每日報告：取消下一個固定ID的每日報告，並重排
        await NotificationService.instance.cancelDailyReportNotification();
        await NotificationService.instance.scheduleDailyReportNotification();

        // 2) 取消並重排今天起未來 N 天（預設 15 天）的事件通知
        await _rescheduleFromToday(uid, days: 15);
      } catch (e) {
        if (kDebugMode) {
          print('處理分組變更時發生錯誤: $e');
        }
      }
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _listeningUid = null;
    _lastAssignment = null;
  }

  /// 重新抓取今天起未來 days 天的事件並重排
  Future<void> _rescheduleFromToday(String uid, {int days = 15}) async {
    final now = DateTime.now();
    for (int i = 0; i < days; i++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      await _cancelAndClearEventNotificationsForDate(uid, day);
      final events = await _fetchFutureEventsForDate(uid, day);
      if (events.isNotEmpty) {
        await NotificationScheduler().sync(events);
      }
    }
  }

  /// 取消並清空特定日期所有事件的通知資訊
  Future<void> _cancelAndClearEventNotificationsForDate(String uid, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startUtc = startOfDay.toUtc();
    final endUtc = endOfDay.toUtc();

    final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, date);
    final snap = await eventsCollection
        .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startUtc))
        .where('scheduledStartTime', isLessThan: Timestamp.fromDate(endUtc))
        .orderBy('scheduledStartTime')
        .get();

    for (final doc in snap.docs) {
      final event = EventModel.fromDoc(doc);
      // 取消兩個事件通知ID（與 NotificationScheduler 的規則一致）
      final hash = event.id.hashCode.abs();
      const base = 1000; // EVENT_NOTIFICATION_ID_BASE
      final firstId = base + (hash % 100000);
      final secondId = -(base + (hash % 100000));
      await NotificationService.instance.cancelNotification(firstId);
      await NotificationService.instance.cancelNotification(secondId);

      // 清空事件文檔中的通知資訊，讓後續 sync 視為未排程
      try {
        final eventDoc = await DataPathService.instance.getDateEventDoc(uid, event.id, event.date ?? startOfDay);
        await eventDoc.update({
          'notifIds': <String>[],
          'notifScheduledAt': FieldValue.delete(),
        });
      } catch (_) {}
    }
  }

  /// 讀取特定日期尚未完成且尚未開始的「未來」事件（含當日未來）
  Future<List<EventModel>> _fetchFutureEventsForDate(String uid, DateTime date) async {
    final now = DateTime.now();
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startUtc = startOfDay.toUtc();
    final endUtc = endOfDay.toUtc();

    final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, date);
    final snap = await eventsCollection
        .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startUtc))
        .where('scheduledStartTime', isLessThan: Timestamp.fromDate(endUtc))
        .orderBy('scheduledStartTime')
        .get();

    final allEvents = snap.docs.map(EventModel.fromDoc).toList();
    final futureEvents = allEvents.where((e) => !e.isDone && e.scheduledStartTime.isAfter(now)).toList();
    return futureEvents;
  }
}


