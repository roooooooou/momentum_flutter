
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // 使用者登入事件
  Future<void> logLogin() async {
    await _analytics.logLogin(loginMethod: 'google');
  }

  // 任務開始事件
  Future<void> logTaskStarted(String source) async {
    await logEvent('task_started', parameters: {'source': source});
  }

  // 自定義事件
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    await _analytics.logEvent(
      name: name,
      parameters: parameters,
    );
  }
} 