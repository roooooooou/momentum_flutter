
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 使用者登入事件
  Future<void> logLogin() async {
    await _analytics.logLogin(loginMethod: 'google');
  }

  // 任務開始事件
  Future<void> logTaskStarted({
    required String userGroup,
    required String taskType,
    required String eventId,
    required String triggerSource,
  }) async {
    print('🎯 GA Event: custom_task_start - group: $userGroup, type: $taskType, eventId: $eventId, source: $triggerSource');
    await logEvent('custom_task_start', userGroup, parameters: {
      'task_type': taskType,
      'event_id': eventId,
      'trigger_source': triggerSource,
    });
  }

  // 任務完成事件
  Future<void> logTaskComplete({
    required String userGroup,
    required String taskType,
    required String eventId,
    required int durationSeconds,
  }) async {
    print('🎯 GA Event: custom_task_complete - group: $userGroup, type: $taskType, eventId: $eventId, duration: ${durationSeconds}s');
    await logEvent('custom_task_complete', userGroup, parameters: {
      'task_type': taskType,
      'event_id': eventId,
      'duration_seconds': durationSeconds,
    });
  }

  // 測驗完成事件
  Future<void> logQuizComplete({
    required String userGroup,
    required String quizType,
    required String eventId,
    required int score,
    required int correctAnswers,
    required int totalQuestions,
    required int durationSeconds,
  }) async {
    print('🎯 GA Event: custom_quiz_complete - group: $userGroup, type: $quizType, eventId: $eventId, score: $score, correct: $correctAnswers/$totalQuestions, duration: ${durationSeconds}s');
    await logEvent('custom_quiz_complete', userGroup, parameters: {
      'quiz_type': quizType,
      'event_id': eventId,
      'score': score,
      'correct_answers': correctAnswers,
      'total_questions': totalQuestions,
      'duration_seconds': durationSeconds,
    });
  }

  // 通知打開事件
  Future<void> logNotificationOpen({
    required String userGroup,
    required String notificationType,
    String? eventId,
  }) async {
    print('🎯 GA Event: notification_opened - group: $userGroup, type: $notificationType, eventId: ${eventId ?? 'N/A'}');
    await logEvent('notification_opened', userGroup, parameters: {
      'notification_type': notificationType,
      if (eventId != null) 'event_id': eventId,
    });
  }

  // 通知互動事件
  Future<void> logNotificationAction({
    required String userGroup,
    required String notificationType,
    required String action,
    String? eventId,
  }) async {
    print('🎯 GA Event: notification_action - group: $userGroup, type: $notificationType, action: $action, eventId: ${eventId ?? 'N/A'}');
    await logEvent('notification_action', userGroup, parameters: {
      'notification_type': notificationType,
      'action': action,
      if (eventId != null) 'event_id': eventId,
    });
  }

  // 學習會話開始事件
  Future<void> logLearningSessionStart({
    required String userGroup,
    required String learningType,
    required String eventId,
    required int itemCount,
  }) async {
    print('🎯 GA Event: learning_session_start - group: $userGroup, type: $learningType, eventId: $eventId, items: $itemCount');
    await logEvent('learning_session_start', userGroup, parameters: {
      'learning_type': learningType,
      'event_id': eventId,
      'item_count': itemCount,
    });
  }

  // 學習會話結束事件
  Future<void> logLearningSessionEnd({
    required String userGroup,
    required String learningType,
    required String eventId,
    required int durationSeconds,
    required int itemsViewed,
    required int totalItems,
  }) async {
    print('🎯 GA Event: learning_session_end - group: $userGroup, type: $learningType, eventId: $eventId, duration: ${durationSeconds}s, viewed: $itemsViewed/$totalItems');
    await logEvent('learning_session_end', userGroup, parameters: {
      'learning_type': learningType,
      'event_id': eventId,
      'duration_seconds': durationSeconds,
      'items_viewed': itemsViewed,
      'total_items': totalItems,
    });
  }

  // 複習會話開始事件
  Future<void> logReviewSessionStart({
    required String userGroup,
    required String reviewType,
    required String eventId,
    required int itemCount,
  }) async {
    print('🎯 GA Event: review_session_start - group: $userGroup, type: $reviewType, eventId: $eventId, items: $itemCount');
    await logEvent('review_session_start', userGroup, parameters: {
      'review_type': reviewType,
      'event_id': eventId,
      'item_count': itemCount,
    });
  }

  // 複習會話結束事件
  Future<void> logReviewSessionEnd({
    required String userGroup,
    required String reviewType,
    required String eventId,
    required int durationSeconds,
    required int itemsViewed,
    required int totalItems,
  }) async {
    print('🎯 GA Event: review_session_end - group: $userGroup, type: $reviewType, eventId: $eventId, duration: ${durationSeconds}s, viewed: $itemsViewed/$totalItems');
    await logEvent('review_session_end', userGroup, parameters: {
      'review_type': reviewType,
      'event_id': eventId,
      'duration_seconds': durationSeconds,
      'items_viewed': itemsViewed,
      'total_items': totalItems,
    });
  }

  // 自定義事件
  Future<void> logEvent(String name, String userGroup, {Map<String, Object>? parameters}) async {
    final eventParameters = {
      'user_group': userGroup,
      ...?parameters,
    };
    await _analytics.logEvent(
      name: name,
      parameters: eventParameters,
    );
  }
} 