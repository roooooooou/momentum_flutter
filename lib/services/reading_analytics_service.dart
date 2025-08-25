import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reading_content_model.dart';
import 'data_path_service.dart';
import 'day_number_service.dart';

class ReadingAnalyticsService {
  static final ReadingAnalyticsService _instance = ReadingAnalyticsService._internal();
  factory ReadingAnalyticsService() => _instance;
  ReadingAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 獲取一個新的會話文檔引用，並根據 source 決定路徑
  Future<DocumentReference> _getNewSessionRef({
    required String uid,
    required String eventId,
    required String source,
  }) async {
    final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
    final sessionId = DateTime.now().toIso8601String();
    
    if (source == 'home_screen_review') {
      // 複習會話
      return eventDoc.collection('review').doc(sessionId);
    } else {
      // 學習會話
      return eventDoc.collection('reading').doc(sessionId);
    }
  }

  /// 根據事件日期計算週次（w0=0, w1=1, w2=2）。若無法判定則回傳0。
  Future<int> _computeWeekFromEvent(String uid, String eventId) async {
    try {
      final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
      final snap = await eventDoc.get();
      if (!snap.exists) return 0;
      final data = snap.data() as Map<String, dynamic>?;
      DateTime? date = (data?['date'] as Timestamp?)?.toDate();
      date ??= (data?['scheduledStartTime'] as Timestamp?)?.toDate();
      if (date == null) return 0;
      final dayNum = await DayNumberService().calculateDayNumber(date.toLocal());
      if (dayNum == 0) return 0;  // w0 測試週
      return dayNum <= 7 ? 1 : 2;  // w1 或 w2
    } catch (_) {
      return 0;
    }
  }

  /// 开始阅读会话，並返回會話文檔的引用
  Future<DocumentReference?> startReadingSession({
    required String uid,
    required String eventId,
    required String source,
    required List<ReadingContent> contents,
  }) async {
    try {
      final ref = await _getNewSessionRef(uid: uid, eventId: eventId, source: source);
      final now = DateTime.now();

      final initialData = {
        'eventId': eventId,
        'startTime': Timestamp.fromDate(now),
        'source': source,
        'totalCards': contents.length,
        'cardDwellTimes': Map.fromIterables(
          List.generate(contents.length, (i) => i.toString()),
          List.filled(contents.length, 0),
        ),
        'totalReadingTime': 0,
        'leaveCount': 0,
        'status': 'active', // active, completed
        'updatedAt': Timestamp.fromDate(now),
      };

      // 如果是複習，額外標記 taskType
      if (source == 'home_screen_review') {
        initialData['taskType'] = 'reading';
      }

      await ref.set(initialData);
      
      // 如果是複習，更新父事件的 activeReviewSessionId
      if (source == 'home_screen_review') {
        final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
        await eventDoc.set({
          'activeReviewSessionId': ref.id,
          'reviewStarted': true, // 確保標記複習已開始
          'updatedAt': Timestamp.fromDate(now),
        }, SetOptions(merge: true));
      }

      return ref;
    } catch (e) {
      print('開始閱讀會話失敗: $e');
      return null;
    }
  }

  /// 记录卡片停留时间
  Future<void> recordCardDwellTime({
    required DocumentReference sessionRef,
    required int cardIndex,
    required int dwellTimeMs,
  }) async {
    try {
      await sessionRef.update({
        'cardDwellTimes.$cardIndex': FieldValue.increment(dwellTimeMs),
        'totalReadingTime': FieldValue.increment(dwellTimeMs),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      print('記錄卡片停留時間失敗: $e');
    }
  }

  /// 记录离开学习页面
  Future<void> recordLeaveSession({
    required DocumentReference sessionRef,
  }) async {
    try {
      await sessionRef.update({
        'leaveCount': FieldValue.increment(1),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      print('記錄離開學習頁面失敗: $e');
    }
  }

  /// (DEPRECATED) 开始测验
  Future<void> startQuiz({
    required String uid,
    required String eventId,
  }) async {
    // This method is deprecated as quiz logic is now handled separately.
  }

  /// 完成测验 (邏輯移至 ReadingQuizScreen)
  Future<void> completeQuiz({
    required String uid,
    required String eventId,
    required int correctAnswers,
    required int totalQuestions,
    int? quizTimeMs, // 新增測驗時間參數
  }) async {
    try {
      // 主要的測驗儲存邏輯已經移到 ReadingQuizScreen -> ReadingAnalyticsService.saveReadingQuizToExperiment
      // 這裡保留更新 event 狀態的兼容代碼，但不再寫入詳細的測驗數據到 reading/analytics
      final eventRef = await DataPathService.instance.getEventDocAuto(uid, eventId);
      final now = DateTime.now();
      
      await eventRef.set({
        'status': 'completed', // 這裡的 status 是 EventModel 的，可能需要重新評估
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

    } catch (e) {
      print('完成测验记录失败: $e');
    }
  }

  /// 儲存閱讀測驗結果
  Future<void> saveReadingQuizToExperiment({
    required String uid,
    required String eventId,
    required List<Map<String, dynamic>> answers,
    required int correctAnswers,
    required int totalQuestions,
    int? quizTimeMs,
  }) async {
    try {
      final now = DateTime.now();
      final score = totalQuestions > 0 ? (correctAnswers / totalQuestions * 100).round() : 0;
      final week = await _computeWeekFromEvent(uid, eventId);
      final quizId = 'reading_w$week';

      final quizDocRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('quiz')
          .doc(quizId);
      
      await quizDocRef.set({
        'type': 'reading',
        'eventId': eventId,
        'week': week,
        'answers': answers,
        'correctAnswers': correctAnswers,
        'totalQuestions': totalQuestions,
        'score': score,
        'quizTimeMs': quizTimeMs ?? 0,
        'savedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

    } catch (e) {
      print('儲存閱讀測驗到 experiment_quiz 失敗: $e');
    }
  }

  /// 完成閱讀會話
  Future<void> completeReadingSession({
    required DocumentReference sessionRef,
  }) async {
    try {
      final now = DateTime.now();
      
      final doc = await sessionRef.get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final startTime = (data['startTime'] as Timestamp).toDate();
      final totalDurationMs = now.difference(startTime).inMilliseconds;

      final updateData = {
        'status': 'completed',
        'endTime': Timestamp.fromDate(now),
        'totalSessionDurationMs': totalDurationMs,
        'updatedAt': Timestamp.fromDate(now),
      };

      // 如果是複習會話，也添加 durationMin 欄位（與原 ExperimentEventHelper 格式相容）
      if (data['taskType'] == 'reading') {
        updateData['durationMin'] = now.difference(startTime).inMinutes;
      }

      await sessionRef.update(updateData);
    } catch (e) {
      print('完成閱讀會話記錄失敗: $e');
    }
  }

  /// (DEPRECATED) 获取阅读会话数据
  Future<Map<String, dynamic>?> getReadingSessionData({
    required String uid,
    required String eventId,
  }) async {
    // This method is deprecated.
    return null;
  }

  /// 获取用户所有阅读会话统计
  Future<Map<String, dynamic>> getUserReadingStats({
    required String uid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // 获取所有事件集合
      final allCollections = await DataPathService.instance.getAllEventsCollections(uid);
      
      int totalSessions = 0;
      int totalReadingTime = 0;
      int totalQuizTime = 0;
      int totalCorrectAnswers = 0;
      int totalQuestions = 0;
      Map<String, int> cardDwellTimes = {};

      for (final collection in allCollections) {
        // 查询所有有reading子集合的事件
        final eventsSnapshot = await collection.get();
        
        for (final eventDoc in eventsSnapshot.docs) {
          try {
            // 查詢新的 sessions 集合
            final sessionsRef = eventDoc.reference.collection('reading');
            final sessionsSnapshot = await sessionsRef.get();

            for (final sessionDoc in sessionsSnapshot.docs) {
              final data = sessionDoc.data();
              final startTime = (data['startTime'] as Timestamp?)?.toDate();
              
              // 检查时间范围
              if (startDate != null && startTime != null && startTime.isBefore(startDate)) continue;
              if (endDate != null && startTime != null && startTime.isAfter(endDate)) continue;
              
              // 只统计已完成的会话
              if (data['status'] == 'completed') {
                totalSessions++;
                totalReadingTime += (data['totalReadingTime'] as num?)?.toInt() ?? 0;
                
                // 註：舊的 quiz 相關統計已從 session 中移除，需要從 quiz 集合單獨計算
                // totalQuizTime += (data['quizTime'] as num?)?.toInt() ?? 0;
                // totalCorrectAnswers += (data['quizCorrectAnswers'] as num?)?.toInt() ?? 0;
                // totalQuestions += (data['quizTotalQuestions'] as num?)?.toInt() ?? 0;

                // 累计卡片停留时间
                final dwellTimes = data['cardDwellTimes'] as Map<String, dynamic>?;
                if (dwellTimes != null) {
                  dwellTimes.forEach((cardIndex, time) {
                    cardDwellTimes[cardIndex] = (cardDwellTimes[cardIndex] ?? 0) + (time as num).toInt();
                  });
                }
             }
            }
          } catch (e) {
            print('處理事件 ${eventDoc.id} 的閱讀數據時出错: $e');
            continue;
          }
        }
      }

      // Quiz 相關的統計需要從 quiz 集合單獨撈取，這裡暫時返回0
      totalQuizTime = 0;
      totalCorrectAnswers = 0;
      totalQuestions = 0;

      return {
        'totalSessions': totalSessions,
        'totalReadingTime': totalReadingTime,
        'totalQuizTime': totalQuizTime,
        'totalCorrectAnswers': totalCorrectAnswers,
        'totalQuestions': totalQuestions,
        'averageScore': totalQuestions > 0 ? (totalCorrectAnswers / totalQuestions * 100).round() : 0,
        'cardDwellTimes': cardDwellTimes,
        'averageReadingTime': totalSessions > 0 ? (totalReadingTime / totalSessions).round() : 0,
        'averageQuizTime': totalSessions > 0 ? (totalQuizTime / totalSessions).round() : 0,
      };
    } catch (e) {
      print('获取用户阅读统计失败: $e');
      return {};
    }
  }
} 