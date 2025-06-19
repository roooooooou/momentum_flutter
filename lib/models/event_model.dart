import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

enum TaskStatus { notStarted, inProgress, overdue, completed }

class EventModel {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final bool isDone;
  final DateTime? actualStartTime;
  final String? googleEventId;
  final String? googleCalendarId;
  final DateTime? updatedAt;
  final int? notifId;
  final DateTime? notifScheduledAt;

  EventModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.isDone,
    this.actualStartTime,
    this.googleEventId,
    this.googleCalendarId,
    this.updatedAt,
    this.notifId,
    this.notifScheduledAt,
  });

  factory EventModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      title: d['title'],
      startTime: (d['startTime'] as Timestamp).toDate(),
      endTime: (d['endTime'] as Timestamp).toDate(),
      isDone: d['isDone'] ?? false,
      actualStartTime: (d['actualStartTime'] as Timestamp?)?.toDate(),
      googleEventId: d['googleEventId'],
      googleCalendarId: d['googleCalendarId'],
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      notifId: d['notifId'],
      notifScheduledAt: (d['notifScheduledAt'] as Timestamp?)?.toDate(),
    );
  }

  String get timeRange {
    final f = DateFormat('HH:mm');
    return '${f.format(startTime.toLocal())} - ${f.format(endTime.toLocal())}';
  }

  TaskStatus get status {
    if (isDone) return TaskStatus.completed;
    if (actualStartTime != null) return TaskStatus.inProgress;
    if (DateTime.now().isAfter(startTime)) return TaskStatus.overdue;
    return TaskStatus.notStarted;
  }

  EventModel copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    bool? isDone,
    DateTime? actualStartTime,
    String? googleEventId,
    String? googleCalendarId,
    DateTime? updatedAt,
    int? notifId,
    DateTime? notifScheduledAt,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isDone: isDone ?? this.isDone,
      actualStartTime: actualStartTime ?? this.actualStartTime,
      googleEventId: googleEventId ?? this.googleEventId,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      updatedAt: updatedAt ?? this.updatedAt,
      notifId: notifId ?? this.notifId,
      notifScheduledAt: notifScheduledAt ?? this.notifScheduledAt,
    );
  }
}
