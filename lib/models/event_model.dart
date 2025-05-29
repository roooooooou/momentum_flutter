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

  EventModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.isDone,
    this.actualStartTime,
    this.googleEventId,
    this.googleCalendarId,
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
}
