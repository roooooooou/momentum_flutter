
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 使用者登入事件
  Future<void> logLogin() async {
    await _analytics.logLogin(loginMethod: 'google');
  }

  // 任務開始事件
  Future<void> logTaskStart({
    required String taskType,
    required String eventId,
    required String triggerSource,
  }) async {
    print('🎯 GA Event: task_start - type: $taskType, eventId: $eventId, source: $triggerSource');
    await logEvent('task_start', parameters: {
      'task_type': taskType,
      'event_id': eventId,
      'trigger_source': triggerSource,
    });
  }

  // 任務完成事件
  Future<void> logTaskComplete({
    required String taskType,
    required String eventId,
    required int durationSeconds,
  }) async {
    print('🎯 GA Event: task_complete - type: $taskType, eventId: $eventId, duration: ${durationSeconds}s');
    await logEvent('task_complete', parameters: {
      'task_type': taskType,
      'event_id': eventId,
      'duration_seconds': durationSeconds,
    });
  }

  // 測驗完成事件
  Future<void> logQuizComplete({
    required String quizType,
    required String eventId,
    required int score,
    required int correctAnswers,
    required int totalQuestions,
    required int durationSeconds,
  }) async {
    print('🎯 GA Event: quiz_complete - type: $quizType, eventId: $eventId, score: $score, correct: $correctAnswers/$totalQuestions, duration: ${durationSeconds}s');
    await logEvent('quiz_complete', parameters: {
      'quiz_type': quizType,
      'event_id': eventId,
      'score': score,
      'correct_answers': correctAnswers,
      'total_questions': totalQuestions,
      'duration_seconds': durationSeconds,
    });
  }

  // 自定義事件
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    await _analytics.logEvent(
      name: name,
      parameters: parameters,
    );
  }
} 