import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import '../models/event_model.dart';

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

  late cal.CalendarApi _api;

  /// Must be called **after** Google Sign-in succeeds.
  Future<void> init(GoogleSignInAccount account) async {
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    _api = cal.CalendarApi(client);
  }

  /// Syncs today's events from *primary* calendar into Firestore `/events`.
  Future<void> syncToday(String uid) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));

    final apiEvents = await _api.events.list(
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
    for (final e in apiEvents.items ?? <cal.Event>[]) {
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
