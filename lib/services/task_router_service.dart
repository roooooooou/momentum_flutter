import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/event_model.dart';
import '../screens/vocab_page.dart';
import '../screens/reading_page.dart';
import '../screens/vocab_quiz_screen.dart';
import '../services/vocab_service.dart';
import '../models/vocab_content_model.dart';
import '../screens/reading_quiz_screen.dart';
import '../services/reading_service.dart';
import '../models/reading_content_model.dart';
import '../services/analytics_service.dart';

class TaskRouterService {
  static const TaskRouterService _instance = TaskRouterService._internal();
  factory TaskRouterService() => _instance;
  const TaskRouterService._internal();

  /// 根据任务标题判断任务类型
  TaskType _getTaskType(String taskTitle) {
    final title = taskTitle.toLowerCase();
    
    print('TaskRouterService: Analyzing task title: "$taskTitle"');
    
    // 測驗頁: vocab-w{week}-test 或 vocab_w{week}_test
    if (RegExp(r'^\s*vocab[-_]?w\d+[-_]?test\s*$', caseSensitive: false).hasMatch(title)) {
      print('TaskRouterService: Identified as vocab quiz task');
      return TaskType.vocabQuiz;
    }

    // 閱讀週測驗頁: reading-w{week}-test（放寬判斷，避免格式差異）
    final readingWeeklyTest = RegExp(r'^\s*reading[-_]?w\d+[-_]?test\s*$', caseSensitive: false);
    if (readingWeeklyTest.hasMatch(title) ||
        title.trim().toLowerCase().startsWith('reading-w') && title.trim().toLowerCase().endsWith('test')) {
      print('TaskRouterService: Identified as reading quiz task');
      return TaskType.readingQuiz;
    }

    // 学习頁: 其他 vocab 類型
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
  void navigateToTaskPage(BuildContext context, EventModel event, {required String source, required String userGroup}) {
    print('🎯 TaskRouterService: Navigating to task page for event: ${event.title}');
    print('🎯 TaskRouterService: Event ID: ${event.id}');
    print('🎯 TaskRouterService: Event Date: ${event.date}');
    print('🎯 TaskRouterService: Event DayNumber: ${event.dayNumber}');
    print('🎯 TaskRouterService: Source: $source');
    print('🎯 TaskRouterService: UserGroup: $userGroup');
    
    // 检查context是否有效
    if (!context.mounted) {
      print('TaskRouterService: Context is not mounted, skipping navigation');
      return;
    }
    
    final taskType = _getTaskType(event.title);
    
    // 記錄 task_start 事件
    AnalyticsService().logTaskStarted(
      userGroup: userGroup,
      taskType: taskType.name,
      eventId: event.id,
      triggerSource: source,
    );
    
    try {
      switch (taskType) {
        case TaskType.vocab:
          print('🎯 TaskRouterService: Navigating to VocabPage');
          final result = Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => VocabPage(event: event, source: source),
            ),
          );
          print('🎯 TaskRouterService: VocabPage navigation initiated: $result');
          break;
        case TaskType.vocabQuiz:
          print('🎯 TaskRouterService: Navigating to VocabQuizScreen');
          final result = Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => _buildQuizRoute(context, event),
            ),
          );
          print('🎯 TaskRouterService: VocabQuizScreen navigation initiated: $result');
          break;
        case TaskType.reading:
          print('🎯 TaskRouterService: Navigating to ReadingPage');
          final result = Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ReadingPage(event: event, source: source),
            ),
          );
          print('🎯 TaskRouterService: ReadingPage navigation initiated: $result');
          break;
        case TaskType.readingQuiz:
          print('🎯 TaskRouterService: Navigating to ReadingQuizScreen');
          final result = Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => _buildReadingQuizRoute(context, event),
            ),
          );
          print('🎯 TaskRouterService: ReadingQuizScreen navigation initiated: $result');
          break;
      }
      print('🎯 TaskRouterService: Navigation switch completed successfully');
    } catch (e) {
      print('🎯 TaskRouterService: Navigation error: $e');
      print('🎯 TaskRouterService: Error details: ${e.toString()}');
    }
  }
}

/// 任务类型枚举
enum TaskType {
  vocab,
  vocabQuiz,
  reading,
  readingQuiz,
} 

// 構建測驗路由（讀取週測驗題庫）
Widget _buildQuizRoute(BuildContext context, EventModel event) {
  final service = VocabService();
  final week = service.parseWeekFromTestTitle(event.title) ?? 1;
  return FutureBuilder(
    future: service.loadWeeklyTestQuiz(week),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      List<VocabContent> questions = (snapshot.data ?? []) as List<VocabContent>;
      // 隨機抽 10 題
      if (questions.length > 10) {
        questions.shuffle();
        questions = questions.take(10).toList();
      }
      return VocabQuizScreen(questions: questions, event: event);
    },
  );
}

// 構建閱讀測驗路由（讀取每日題庫）
Widget _buildReadingQuizRoute(BuildContext context, EventModel event) {
  final week = _parseWeekFromReadingTest(event.title) ?? 1;
  return FutureBuilder(
    future: _loadWeeklyReadingQuestions(week),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      List<ReadingQuestion> questions = (snapshot.data ?? []) as List<ReadingQuestion>;
      // 依 rid 去重，每篇文章最多一題，並隨機抽 10 題
      if (questions.isNotEmpty) {
        questions.shuffle();
        final seenRid = <String>{};
        final unique = <ReadingQuestion>[];
        for (final q in questions) {
          final rid = q.rid;
          if (rid.isNotEmpty && seenRid.contains(rid)) continue;
          seenRid.add(rid);
          unique.add(q);
          if (unique.length >= 10) break;
        }
        questions = unique.length <= 10 ? unique : unique.take(10).toList();
      }
      return ReadingQuizScreen(questions: questions, event: event);
    },
  );
}

int? _parseWeekFromReadingTest(String title) {
  final lower = title.toLowerCase().trim();
  final patterns = <RegExp>[
    RegExp(r'^reading[-_]?w(\d+)[-_]?test$'),
    RegExp(r'^reading[-_]?(\d+)[-_]?test$'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(lower);
    if (m != null && m.groupCount >= 1) {
      final w = int.tryParse(m.group(1)!);
      if (w != null) return w;
    }
  }
  return null;
}

Future<List<ReadingQuestion>> _loadWeeklyReadingQuestions(int week) async {
  try {
    final path = 'assets/dyn/week${week}_test.json';
    final jsonString = await rootBundle.loadString(path);
    final Map<String, dynamic> data = json.decode(jsonString) as Map<String, dynamic>;
    final Map<String, dynamic> days = (data['days'] as Map<String, dynamic>?) ?? {};
    final List<ReadingQuestion> out = [];
    
    // 只載入 day1-5 的題目，排除 day6
    for (final entry in days.entries) {
      final dayKey = entry.key;
      // 跳過 day6 的題目
      if (dayKey == 'day6') {
        continue;
      }
      
      final List<dynamic> items = (entry.value as List?) ?? [];
      for (final it in items) {
        final Map<String, dynamic> m = it as Map<String, dynamic>;
        final String rid = (m['rid'] ?? '').toString();
        final List<dynamic> qList = (m['questions'] as List?) ?? [];
        out.addAll(qList.map((q) => ReadingQuestion.fromJson(q as Map<String, dynamic>, rid: rid)));
      }
    }
    return out;
  } catch (e) {
    print('TaskRouterService: load weekly reading questions failed: $e');
    return [];
  }
}