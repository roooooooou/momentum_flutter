import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:momentum/services/auth_service.dart';
import '../models/event_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    _api = cal.CalendarApi(client);
    
    // 載入上次同步時間
    await _loadLastSyncAt();
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
    if (_api != null) return;
    final acct = AuthService.instance.googleAccount;
    if (acct != null) {
      try {
        await init(acct);
      } catch (e) {
        // 如果初始化失败，尝试重新登录
        await AuthService.instance.signInSilently();
        final newAcct = AuthService.instance.googleAccount;
        if (newAcct != null) {
          await init(newAcct);
        } else {
          throw StateError('CalendarService initialization failed');
        }
      }
    } else {
      throw StateError('CalendarService not initialized');
    }
  }

  /// 增量同步：從指定時間開始同步
  Future<void> _syncFrom(String uid, DateTime updatedMin) async {
    await _ensureReady();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));

    final apiEvents = await _api!.events.list(
      'primary',
      timeMin: updatedMin.toUtc(),
      timeMax: end,
      singleEvents: true,
      orderBy: 'startTime',
      updatedMin: updatedMin.toUtc(),
    );

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events');

    final idsToday = <String>{};

    // 1) 逐筆 upsert，處理時間戳衝突
    for (final e in apiEvents!.items ?? <cal.Event>[]) {
      final s = e.start?.dateTime, t = e.end?.dateTime;
      if (s == null || t == null) continue;

      final ref = col.doc(e.id);
      final snap = await ref.get();

      // 檢查時間戳衝突
      if (snap.exists) {
        final existingData = snap.data()!;
        final existingUpdated = existingData['updatedAt'] as Timestamp?;
        final eventUpdated = e.updated;
        
        if (existingUpdated != null && eventUpdated != null) {
          final existingTime = existingUpdated.toDate();
          final eventTime = eventUpdated.toUtc();
          
          // last-write-wins 策略
          if (existingTime.isAfter(eventTime)) {
            idsToday.add(e.id!);
            continue; // 跳過這個事件，保留本地數據
          }
        }
      }

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
    }

    // 2) 移除 Google 已刪除的（可選）
    final snap = await col
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      if (!idsToday.contains(d.id)) {
        batch.delete(d.reference);
      }
    }
    await batch.commit();
  }

  /// App Resume 增量同步
  Future<void> resumeSync(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    _isSyncing = true;
    try {
      final now = DateTime.now();
      final updatedMin = _lastSyncAt ?? DateTime(now.year, now.month, now.day);
      
      // 執行增量同步
      await _syncFrom(uid, updatedMin);
      
      // 更新並儲存lastSyncAt
      await _saveLastSyncAt(now);
    } catch (e) {
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// Syncs today's events from *primary* calendar into Firestore `/events`.
  Future<void> syncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    _isSyncing = true;
    try {
      await _ensureReady();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 1));

      final apiEvents = await _api!.events.list(
        'primary',
        timeMin: start,
        timeMax: end,
        singleEvents: true,
        orderBy: 'startTime',
      );

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
      }

      // 2) 移除 Google 已刪除的（可選）
      final snap = await col
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('startTime', isLessThan: Timestamp.fromDate(end))
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        if (!idsToday.contains(d.id)) batch.delete(d.reference);
      }
      await batch.commit();
      
      // 更新並儲存lastSyncAt
      await _saveLastSyncAt(now);
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

    await doc.update({
      'isDone': newDone,
      'doneAt': newDone ? Timestamp.now() : null,
    });
  }

  Future<void> startEvent(String uid, EventModel e) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(e.id);

    await ref.update({
      'actualStartTime': Timestamp.now(), // 記錄開始時間
      'isDone': false, // 保險起見，確保還沒完成
    });
  }

  Future<void> stopEvent(String uid, EventModel e) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(e.id);

    await ref.update({
      'actualStartTime': null, // 清掉開始時間 → 讓 status 回 NotStart / Overdue
    });
  }

  Future<void> completeEvent(String uid, EventModel e) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(e.id);

    await ref.update({
      'isDone': true,
      'doneAt': Timestamp.now(),
    });
  }
}
