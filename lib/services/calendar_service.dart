import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:momentum/services/auth_service.dart';
import '../models/event_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:flutter/foundation.dart';

/// Light wrapper that adds Google OAuth headers to each request.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class CalendarService {
  CalendarService._();
  static final instance = CalendarService._();

  cal.CalendarApi? _api;
  DateTime? _lastSyncAt;
  bool _isSyncing = false;
  
  // Getters for UI state
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Must be called **after** Google Sign-in succeeds.
  Future<void> init(GoogleSignInAccount account) async {
    try {
      final authHeaders = await account.authHeaders;
      final client = _GoogleAuthClient(authHeaders);
      _api = cal.CalendarApi(client);
      
      // 測試 API 是否正常工作
      await _api!.calendarList.list();
      
      // 載入上次同步時間
      await _loadLastSyncAt();
      
      if (kDebugMode) {
        print('CalendarService 初始化成功');
      }
    } catch (e) {
      _api = null; // 重置 API 實例
      if (kDebugMode) {
        print('CalendarService 初始化失敗: $e');
      }
      rethrow;
    }
  }

  /// 從SharedPreferences載入lastSyncAt
  Future<void> _loadLastSyncAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTimestamp = prefs.getInt('last_sync_at');
      if (lastSyncTimestamp != null) {
        _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp);
      }
    } catch (e) {
      // 如果載入失敗，使用預設值
      _lastSyncAt = null;
    }
  }

  /// 儲存lastSyncAt到SharedPreferences
  Future<void> _saveLastSyncAt(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_at', timestamp.millisecondsSinceEpoch);
      _lastSyncAt = timestamp;
    } catch (e) {
      // 如果儲存失敗，至少更新記憶體中的值
      _lastSyncAt = timestamp;
    }
  }

  Future<void> _ensureReady() async {
    if (kDebugMode) {
      print('_ensureReady: 開始檢查 API 狀態');
    }
    
    if (_api != null) {
      // 测试 API 是否仍然有效
      try {
        if (kDebugMode) {
          print('_ensureReady: 測試現有 API 實例');
        }
        await _api!.calendarList.list();
        if (kDebugMode) {
          print('_ensureReady: API 實例有效，直接返回');
        }
        return; // API 仍然有效
      } catch (e) {
        if (kDebugMode) {
          print('_ensureReady: Calendar API 測試失敗，需要重新初始化: $e');
        }
        // API 無效，重置並重新初始化
        _api = null;
      }
    }
    
    if (kDebugMode) {
      print('_ensureReady: 開始重新初始化 API');
    }
    
    final acct = AuthService.instance.googleAccount;
    if (acct != null) {
      try {
        if (kDebugMode) {
          print('_ensureReady: 使用現有帳號初始化: ${acct.email}');
        }
        await init(acct);
        if (kDebugMode) {
          print('_ensureReady: 使用現有帳號初始化成功');
        }
      } catch (e) {
        if (kDebugMode) {
          print('_ensureReady: 使用現有帳號初始化失敗: $e');
        }
        // 如果初始化失败，尝试重新登录
        try {
          if (kDebugMode) {
            print('_ensureReady: 嘗試重新登入');
          }
          await AuthService.instance.signInSilently();
          final newAcct = AuthService.instance.googleAccount;
          if (newAcct != null) {
            if (kDebugMode) {
              print('_ensureReady: 使用新帳號初始化: ${newAcct.email}');
            }
            await init(newAcct);
            if (kDebugMode) {
              print('_ensureReady: 使用新帳號初始化成功');
            }
          } else {
            throw StateError('無法獲取有效的 Google 帳號');
          }
        } catch (signInError) {
          if (kDebugMode) {
            print('_ensureReady: 重新登入失敗: $signInError');
          }
          throw StateError('CalendarService 初始化失敗: $signInError');
        }
      }
    } else {
      if (kDebugMode) {
        print('_ensureReady: 沒有可用的 Google 帳號');
      }
      throw StateError('CalendarService 未初始化');
    }
  }

  /// 強制完整同步今日事件（手動觸發）
  Future<void> forceSyncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('手動觸發完整同步');
    }
    
    await syncToday(uid);
  }

  /// App Resume 同步
  Future<void> resumeSync(String uid) async {
    if (kDebugMode) {
      print('App Resume: 開始同步');
    }
    
    // 直接使用 syncToday，因為邏輯完全一樣
    await syncToday(uid);
  }

  /// Syncs today's events from *primary* calendar into Firestore `/events`.
  Future<void> syncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('syncToday: 開始同步，UID: $uid');
    }
    
    _isSyncing = true;
    try {
      await _ensureReady();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 1));

      if (kDebugMode) {
        print('syncToday: 查詢 Google Calendar 事件，時間範圍: $start 到 $end');
      }

      final apiEvents = await _api!.events.list(
        'primary',
        timeMin: start,
        timeMax: end,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (kDebugMode) {
        print('syncToday: 從 Google Calendar 獲取到 ${apiEvents!.items?.length ?? 0} 個事件');
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events');

      final idsToday = <String>{};

      // 1) 逐筆 upsert
      for (final e in apiEvents!.items ?? <cal.Event>[]) {
        final s = e.start?.dateTime, t = e.end?.dateTime;
        if (s == null || t == null) continue;

        final ref = col.doc(e.id);
        final snap = await ref.get(); // 先判斷有沒有這筆

        final data = <String, dynamic>{
          'title': e.summary ?? 'No title',
          'startTime': Timestamp.fromDate(s.toUtc()),
          'endTime': Timestamp.fromDate(t.toUtc()),
          'googleEventId': e.id,
          'googleCalendarId': e.organizer?.email ?? 'primary',
          'updatedAt': Timestamp.fromDate(e.updated?.toUtc() ?? now.toUtc()),
          if (!snap.exists) 'isDone': false,
        };

        await ref.set(data, SetOptions(merge: true));
        idsToday.add(e.id!);
        
        if (kDebugMode) {
          print('syncToday: 同步事件: ${e.summary} (ID: ${e.id})');
        }
      }

      // 2) 移除 Google 已刪除的事件
      final snap = await col
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('startTime', isLessThan: Timestamp.fromDate(end))
          .get();

      final batch = FirebaseFirestore.instance.batch();
      final deletedEvents = <String>[];
      
      if (kDebugMode) {
        print('syncToday: API 返回的事件 ID: ${idsToday.toList()}');
        print('syncToday: 本地事件數量: ${snap.docs.length}');
      }
      
      for (final d in snap.docs) {
        if (kDebugMode) {
          print('syncToday: 檢查本地事件: ${d.data()['title']} (ID: ${d.id})');
        }
        
        if (!idsToday.contains(d.id)) {
          // 在刪除前取消通知
          final data = d.data();
          final notifId = data['notifId'] as int?;
          final secondNotifId = data['secondNotifId'] as int?;
          if (notifId != null || secondNotifId != null) {
            await NotificationScheduler().cancelEventNotification(d.id, notifId, secondNotifId);
          }
          
          batch.delete(d.reference);
          deletedEvents.add(d.id);
          if (kDebugMode) {
            print('syncToday: 刪除事件: ${data['title']} (ID: ${d.id})');
          }
        } else {
          if (kDebugMode) {
            print('syncToday: 保留事件: ${d.data()['title']} (ID: ${d.id})');
          }
        }
      }
      
      if (deletedEvents.isNotEmpty) {
        await batch.commit();
        if (kDebugMode) {
          print('syncToday: 已刪除 ${deletedEvents.length} 個事件');
        }
      }
      
      // 3) 重新讀取今日所有事件，用於通知排程
      final updatedSnap = await col
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('startTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('startTime')
          .get();
      
      final events = updatedSnap.docs.map(EventModel.fromDoc).toList();
      
      // 4) 同步通知排程
      if (events.isNotEmpty) {
        await NotificationScheduler().sync(events);
        if (kDebugMode) {
          print('syncToday: 同步了 ${events.length} 個事件的通知排程');
        }
      }
      
      // 更新並儲存lastSyncAt
      await _saveLastSyncAt(now);
      
      if (kDebugMode) {
        print('syncToday: 同步完成');
      }
    } catch (e) {
      if (kDebugMode) {
        print('syncToday: 同步失敗: $e');
      }
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> toggleEventDone(String uid, EventModel event,
      {bool pushToCalendar = false}) async {
    final newDone = !event.isDone;

    // 1) Firestore update
    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(event.id);

    await doc.set({
      'isDone': newDone,
      'doneAt': newDone ? Timestamp.now() : null,
    }, SetOptions(merge: true));
  }

  Future<void> startEvent(String uid, EventModel e) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(e.id);

    await ref.set({
      'actualStartTime': Timestamp.now(), // 記錄開始時間
      'isDone': false, // 保險起見，確保還沒完成
    }, SetOptions(merge: true));
    
    // 取消第二個通知（因為任務已經開始）
    if (e.secondNotifId != null) {
      await NotificationScheduler().cancelSecondNotification(e.id, e.secondNotifId);
    }
  }

  Future<void> stopEvent(String uid, EventModel e) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(e.id);

    await ref.set({
      'actualStartTime': null, // 清掉開始時間 → 讓 status 回 NotStart / Overdue
    }, SetOptions(merge: true));
  }

  Future<void> completeEvent(String uid, EventModel e) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(e.id);

    await ref.set({
      'isDone': true,
      'doneAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }
}
