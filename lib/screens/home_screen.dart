import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

import '../services/auth_service.dart';
import '../services/task_service.dart';
import '../providers/tasks_provider.dart';
import '../widgets/task_item.dart';
import '../models/task_model.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> fetchAndStoreGoogleTasks(BuildContext context) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = await auth.getAccessToken();
    final uid = auth.currentUser?.uid;

    if (token == null || uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未登入或無法取得權限')),
      );
      return;
    }

    final response = await http.get(
      Uri.parse('https://tasks.googleapis.com/tasks/v1/lists/@default/tasks'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      final tasks = jsonData['items'] as List<dynamic>?;

      if (tasks != null) {
        for (var item in tasks) {
          final googleTaskId = item['id'] as String?;
          final taskListId = item['parent'] ?? '@default';
          final title = item['title'] ?? '無標題';
          final status = item['status'] ?? 'needsAction';
          final dueStr = item['due'] as String?;
          final description = item['notes'] ?? '';
          final dueTime = dueStr != null ? DateTime.tryParse(dueStr) : null;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .doc(googleTaskId)
              .set({
            'title': title,
            'description': description,
            'dueTime': dueTime != null ? Timestamp.fromDate(dueTime) : null,
            'isDone': status == 'completed',
            'doneAt': status == 'completed' ? Timestamp.now() : null,
            'googleTaskListId': taskListId,
            'googleTaskId': googleTaskId,
          });
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已同步 Google Tasks 任務')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取得失敗: ${response.statusCode}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final tasksProvider = Provider.of<TasksProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Tasks"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: '同步 Google Tasks',
            onPressed: () => fetchAndStoreGoogleTasks(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
          ),
        ],
      ),
      body: tasksProvider.taskStream == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Task>>(
              stream: tasksProvider.taskStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final tasks = snapshot.data!;
                if (tasks.isEmpty) {
                  return const Center(child: Text('No tasks for today.'));
                }
                return ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => TaskItem(
                    task: tasks[index],
                    onChanged: (_) async {
                      tasksProvider.toggleTask(tasks[index]);
                      if (tasks[index].googleTaskId != null) {
                        final accessToken = await auth.getAccessToken();
                        if (tasks[index].googleTaskId != null) {
                          await updateGoogleTaskStatus(
                            tasks[index].taskListId!,
                            tasks[index].googleTaskId!,
                            !tasks[index].isDone,
                            accessToken!,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已更新 Google Tasks Status'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
