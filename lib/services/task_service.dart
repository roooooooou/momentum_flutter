import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TasksService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Task>> getTodayTasks(String uid) {
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .where('dueTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dueTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('dueTime')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Task.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> toggleTaskDone(String uid, Task task) async {
    print('🟡 正在更新 Firestore task: ${task.googleTaskId}');
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('tasks')
        .doc(task.googleTaskId);
    await ref.update({
      'isDone': !task.isDone,
      'doneAt': !task.isDone
          ? FieldValue.serverTimestamp()
          : FieldValue.delete(), // 用 delete() 明確刪掉
    });
  }
}

Future<void> updateGoogleTaskStatus(
    String taskListId, String taskId, bool isDone, String accessToken) async {
  final url = Uri.parse(
      'https://tasks.googleapis.com/tasks/v1/lists/$taskListId/tasks/$taskId');

  final body = jsonEncode({
    'status': isDone ? 'completed' : 'needsAction',
  });

  final response = await http.patch(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: body,
  );

  if (response.statusCode != 200) {
    throw Exception('Google Task 更新失敗: ${response.body}');
  }
}
