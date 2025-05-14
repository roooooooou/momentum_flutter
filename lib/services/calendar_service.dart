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

    final events = await _api.events.list(
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

    for (final e in events.items ?? <cal.Event>[]) {
      final startDt = e.start?.dateTime;
      final endDt = e.end?.dateTime;
      if (startDt == null || endDt == null) continue;

      await col.doc(e.id).set({
        'title': e.summary ?? 'No title',
        'startTime': Timestamp.fromDate(startDt.toUtc()),
        'endTime': Timestamp.fromDate(endDt.toUtc()),
        'googleEventId': e.id,
        'googleCalendarId': e.organizer?.email ?? 'primary',
        'isDone': false,
      });
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
}
