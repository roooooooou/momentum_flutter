import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vocab_content_model.dart';
import 'data_path_service.dart';
import 'day_number_service.dart';

class VocabAnalyticsService {
  static final VocabAnalyticsService _instance = VocabAnalyticsService._internal();
  factory VocabAnalyticsService() => _instance;
  VocabAnalyticsService._internal();

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
      return eventDoc.collection('vocab').doc(sessionId);
    }
  }

  /// 獲取詞彙學習數據文檔引用（用於舊的 startQuiz 和 completeQuiz 方法）
  Future<DocumentReference> _getVocabDataRef({
    required String uid,
    required String eventId,
  }) async {
    final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
    // 使用固定的文檔ID 'vocab_data' 來存儲詞彙學習數據
    return eventDoc.collection('vocab').doc('vocab_data');
  }

  /// 儲存詞彙測驗結果到 users/{uid}/experiment_quiz/{quizId}
  Future<void> saveVocabQuizToExperiment({
    required String uid,
    required String quizId,
    required List<Map<String, dynamic>> answers,
    required int correctAnswers,
    required int totalQuestions,
    String? eventId,
    int? week,
    int? quizTimeMs, // 新增測驗時間參數
  }) async {
    try {
      final now = DateTime.now();
      final score = totalQuestions > 0 ? (correctAnswers / totalQuestions * 100).round() : 0;
      // 以事件日期計算週次；若無 eventId 則回退為傳入參數或0
      int resolvedWeek = week ?? 0;
      if (resolvedWeek == 0 && eventId != null && eventId.isNotEmpty) {
        try {
          final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
          final snap = await eventDoc.get();
          if (snap.exists) {
            final data = snap.data() as Map<String, dynamic>?;
            DateTime? date = (data?['date'] as Timestamp?)?.toDate();
            date ??= (data?['scheduledStartTime'] as Timestamp?)?.toDate();
            if (date != null) {
              final dayNum = await DayNumberService().calculateDayNumber(date.toLocal());
              if (dayNum == 0) {
                resolvedWeek = 0;  // w0 測試週
              } else {
                resolvedWeek = dayNum <= 7 ? 1 : 2;  // w1 或 w2
              }
            }
          }
        } catch (_) {}
      }

      // 統一命名：vocab 以週為單位 → vocab_w{week}
      final standardizedQuizDocId = 'vocab_w$resolvedWeek';
      
      // 儲存測驗結果到簡化路徑：users/{uid}/quiz/vocab_w{week}
      final quizDocRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('quiz')
          .doc(standardizedQuizDocId);
      
      // 直接儲存到 quiz 集合，不使用 attempts 子集合
      await quizDocRef.set({
        'type': 'vocab',
        'eventId': eventId,
        'week': resolvedWeek,
        'answers': answers,
        'correctAnswers': correctAnswers,
        'totalQuestions': totalQuestions,
        'score': score,
        'quizTimeMs': quizTimeMs ?? 0, // 新增測驗時間（毫秒）
        'savedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    } catch (e) {
      print('儲存詞彙測驗到 experiment_quiz 失敗: $e');
    }
  }

  // 舊 attempts 版本已移除，不再使用

  /// 开始词汇学习会话，並返回會話文檔的引用
  Future<DocumentReference?> startVocabSession({
    required String uid,
    required String eventId,
    required String source,
    required List<VocabContent> vocabList,
  }) async {
    try {
      final ref = await _getNewSessionRef(uid: uid, eventId: eventId, source: source);
      final now = DateTime.now();

      final initialData = {
        'eventId': eventId,
        'startTime': Timestamp.fromDate(now),
        'source': source,
        'totalWords': vocabList.length,
        'cardDwellTimes': Map.fromIterables(
          List.generate(vocabList.length, (i) => i.toString()),
          List.filled(vocabList.length, 0),
        ),
        'totalLearningTime': 0,
        'leaveCount': 0,
        'status': 'active', // active, completed
        'updatedAt': Timestamp.fromDate(now),
      };

      // 如果是複習，額外標記 taskType
      if (source == 'home_screen_review') {
        initialData['taskType'] = 'vocab';
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
      print('開始詞彙學習會話失敗: $e');
      return null;
    }
  }

  /// 完成詞彙學習會話
  Future<void> completeLearningSession({
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
      if (data['taskType'] == 'vocab') {
        updateData['durationMin'] = now.difference(startTime).inMinutes;
      }

      await sessionRef.update(updateData);
    } catch (e) {
      print('完成詞彙學習會話記錄失敗: $e');
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
        'totalLearningTime': FieldValue.increment(dwellTimeMs),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      // 如果文檔可能不存在，可以考慮在這裡做一個 get and set 的回退，但理論上 sessionRef 應該是有效的
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

  /// 開始測驗（已不再使用，保留以避免舊代碼呼叫報錯）
  Future<void> startQuiz({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getVocabDataRef(uid: uid, eventId: eventId);
      final now = DateTime.now();
      
      await ref.update({
        'updatedAt': Timestamp.fromDate(now),
      });
    } catch (e) {
      print('開始測驗記錄失敗: $e');
    }
  }

  /// 完成測驗（已不再使用，保留以避免舊代碼呼叫報錯）
  Future<void> completeQuiz({
    required String uid,
    required String eventId,
    required int correctAnswers,
    required int totalQuestions,
  }) async {
    try {
      final ref = await _getVocabDataRef(uid: uid, eventId: eventId);
      final now = DateTime.now();
      
      // 获取当前数据来计算测验时间
      final doc = await ref.get();
      if (doc.exists) {
        // no-op: 不再計算 quiz 時間
      }
      await ref.update({
        'status': 'completed',
        'endTime': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    } catch (e) {
      print('完成測驗記錄失敗: $e');
    }
  }

  /// (DEPRECATED) 获取词汇学习会话数据 - 應改為查詢特定 session
  Future<Map<String, dynamic>?> getVocabSessionData({
    required String uid,
    required String eventId,
  }) async {
    // 這個方法現在邏輯上已經過時，因為一個 event 可能有多個 session
    // 應在調用處直接處理 session document
    return null;
  }

  /// 獲取用戶所有詞彙學習統計（已移除 quiz 統計）
  Future<Map<String, dynamic>> getUserVocabStats({
    required String uid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // 获取所有事件集合
      final allCollections = await DataPathService.instance.getAllEventsCollections(uid);
      
      int totalSessions = 0;
      int totalLearningTime = 0;
      int totalQuizTime = 0; // 兼容舊回傳鍵，固定為0
      int totalCorrectAnswers = 0; // 兼容舊回傳鍵，固定為0
      int totalQuestions = 0; // 兼容舊回傳鍵，固定為0
      Map<String, int> cardDwellTimes = {};

      for (final collection in allCollections) {
        // 查询所有有vocab子集合的事件
        final eventsSnapshot = await collection.get();
        
        for (final eventDoc in eventsSnapshot.docs) {
          try {
            // 查詢新的 learning_sessions 集合
            final sessionsRef = eventDoc.reference.collection('vocab');
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
                totalLearningTime += (data['totalLearningTime'] as num?)?.toInt() ?? 0;

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
            print('處理詞彙數據時出錯: $e');
            continue;
          }
        }
      }

      return {
        'totalSessions': totalSessions,
        'totalLearningTime': totalLearningTime,
        'totalQuizTime': totalQuizTime,
        'totalCorrectAnswers': totalCorrectAnswers,
        'totalQuestions': totalQuestions,
        'averageScore': 0,
        'cardDwellTimes': cardDwellTimes,
      };
    } catch (e) {
      print('獲取詞彙學習統計失敗: $e');
      return {
        'totalSessions': 0,
        'totalLearningTime': 0,
        'totalQuizTime': 0,
        'totalCorrectAnswers': 0,
        'totalQuestions': 0,
        'averageScore': 0,
        'cardDwellTimes': {},
      };
    }
  }
} 