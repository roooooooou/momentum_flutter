import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/task_model.dart';

class TasksProvider extends ChangeNotifier {
  User? _user;
  final List<Task> _tasks = [];
  Stream<List<Task>>? _taskStream;

  void setUser(User? user) {
    _user = user;
    if (user != null) {
      _taskStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => Task.fromMap(doc.id, doc.data()))
              .toList());
      notifyListeners();
    }
  }

  Stream<List<Task>>? get taskStream => _taskStream;

  Future<void> toggleTask(Task task) async {
    if (_user == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .collection('tasks')
        .doc(task.googleTaskId);
    await ref.update({
      'isDone': !task.isDone,
      'doneAt': !task.isDone ? FieldValue.serverTimestamp() : null,
    });
  }
}
