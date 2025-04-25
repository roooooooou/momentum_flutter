// lib/widgets/task_item.dart
import 'package:flutter/material.dart';
import '../models/task_model.dart';

class TaskItem extends StatelessWidget {
  final Task task;
  final void Function(bool?)? onChanged;

  const TaskItem({super.key, required this.task, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      title: Text(task.title,
          style: task.isDone
              ? const TextStyle(
                  decoration: TextDecoration.lineThrough, color: Colors.grey)
              : null),
      subtitle: Text('${task.discription} Due: ${task.dueTime}'),
      value: task.isDone,
      onChanged: onChanged,
    );
  }
}
