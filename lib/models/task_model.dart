import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String title;
  final DateTime dueTime;
  final bool isDone;
  final DateTime? doneAt;
  final String? discription;
  final String? googleTaskId;
  final String? taskListId;

  Task({
    required this.title,
    required this.dueTime,
    required this.isDone,
    required this.googleTaskId,
    required this.taskListId,
    this.discription = '',
    this.doneAt,
  });

  factory Task.fromMap(String id, Map<String, dynamic> data) => Task(
        googleTaskId: data['googleTaskId'],
        taskListId: data['googleTaskListId'],
        title: data['title'],
        dueTime: (data['dueTime'] as Timestamp).toDate(),
        discription: data['description'] ?? '',
        isDone: data['isDone'],
        doneAt: data['doneAt'] != null
            ? (data['doneAt'] as Timestamp).toDate()
            : null,
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'dueTime': dueTime,
        'isDone': isDone,
        'doneAt': doneAt,
      };
}
