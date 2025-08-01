import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../screens/vocab_page.dart';
import '../screens/reading_page.dart';

class TaskRouterService {
  static const TaskRouterService _instance = TaskRouterService._internal();
  factory TaskRouterService() => _instance;
  const TaskRouterService._internal();

  /// 根据任务标题判断任务类型
  TaskType _getTaskType(String taskTitle) {
    final title = taskTitle.toLowerCase();
    
    print('TaskRouterService: Analyzing task title: "$taskTitle"');
    
    // 检查是否包含词汇相关关键词
    if (title.contains('vocab')) {
      print('TaskRouterService: Identified as vocab task');
      return TaskType.vocab;
    }
    
    // 检查是否包含阅读相关关键词
    if (title.contains('reading')) {
      print('TaskRouterService: Identified as reading task');
      return TaskType.reading;
    }
    
    // 默认返回阅读类型
    print('TaskRouterService: Defaulting to reading task');
    return TaskType.reading;
  }

  /// 根据任务跳转到相应页面
  void navigateToTaskPage(BuildContext context, EventModel event) {
    print('TaskRouterService: Navigating to task page for event: ${event.title}');
    
    final taskType = _getTaskType(event.title);
    
    switch (taskType) {
      case TaskType.vocab:
        print('TaskRouterService: Navigating to VocabPage');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VocabPage(event: event),
          ),
        );
        break;
      case TaskType.reading:
        print('TaskRouterService: Navigating to ReadingPage');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ReadingPage(event: event),
          ),
        );
        break;
    }
  }
}

/// 任务类型枚举
enum TaskType {
  vocab,
  reading,
} 