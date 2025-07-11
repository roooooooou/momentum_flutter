import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

/// 应用使用数据收集服务
class AppUsageService {
  AppUsageService._();
  static final instance = AppUsageService._();

  final _firestore = FirebaseFirestore.instance;
  DateTime? _sessionStartTime;
  bool _openedByNotification = false;
  String? _currentSessionId; // 🎯 新增：记录当前会话ID

  /// 记录应用打开（在app启动时调用）
  Future<void> recordAppOpen({bool fromNotification = false}) async {
    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) return;

      _sessionStartTime = DateTime.now();
      _openedByNotification = fromNotification;

      final today = _getTodayDateString();
      final sessionId = _generateSessionId();
      _currentSessionId = sessionId; // 🎯 保存会话ID供关闭时使用
      
      final ref = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('app_sessions')
          .doc(sessionId);

      await ref.set({
        'start_time': Timestamp.fromDate(_sessionStartTime!),
        'end_time': null,
        'duration_seconds': null,
        'opened_by_notification': fromNotification,
        'date': today,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('AppUsageService: 记录应用打开, fromNotification: $fromNotification');
      }
    } catch (e) {
      if (kDebugMode) {
        print('AppUsageService: 记录应用打开失败: $e');
      }
    }
  }

  /// 记录应用关闭（在app暂停/后台时调用）
  Future<void> recordAppClose() async {
    try {
      if (_sessionStartTime == null || _currentSessionId == null) return;

      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) return;

      final endTime = DateTime.now();
      final durationSeconds = endTime.difference(_sessionStartTime!).inSeconds;
      
      // 只记录超过5秒的会话，避免误触
      if (durationSeconds < 5) {
        // 重置状态但不记录
        _sessionStartTime = null;
        _currentSessionId = null;
        _openedByNotification = false;
        return;
      }

      final ref = _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('app_sessions')
          .doc(_currentSessionId!); // 🎯 使用保存的会话ID

      await ref.update({
        'end_time': Timestamp.fromDate(endTime),
        'duration_seconds': durationSeconds,
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('AppUsageService: 记录应用关闭, 使用时长: ${durationSeconds}秒');
      }

      // 重置状态
      _sessionStartTime = null;
      _currentSessionId = null;
      _openedByNotification = false;
    } catch (e) {
      if (kDebugMode) {
        print('AppUsageService: 记录应用关闭失败: $e');
      }
    }
  }

  /// 生成会话ID
  String _generateSessionId() {
    final now = DateTime.now();
    return 'session_${now.millisecondsSinceEpoch}';
  }

  /// 获取今日日期字符串 (YYYYMMDD)
  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
} 