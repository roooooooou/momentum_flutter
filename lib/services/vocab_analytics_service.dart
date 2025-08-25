import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vocab_content_model.dart';
import 'data_path_service.dart';
import 'day_number_service.dart';

class VocabAnalyticsService {
  static final VocabAnalyticsService _instance = VocabAnalyticsService._internal();
  factory VocabAnalyticsService() => _instance;
  VocabAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 获取词汇数据文档引用（自動解析事件所在集合）
  Future<DocumentReference> _getVocabDataRef(String uid, String eventId) async {
    final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
    return eventDoc.collection('vocab').doc('analytics');
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

  /// 开始词汇学习会话
  Future<void> startVocabSession({
    required String uid,
    required String eventId,
    required List<VocabContent> vocabList,
  }) async {
    final now = DateTime.now();
    final sessionId = 'vocab_${eventId}_${now.millisecondsSinceEpoch}';
    final ref = await _getVocabDataRef(uid, eventId);
    
    // 检查是否已有会话数据
    final existingDoc = await ref.get();
    Map<String, dynamic> existingData = {};
    if (existingDoc.exists) {
      existingData = existingDoc.data() as Map<String, dynamic>;
    }
    
    await ref.set({
      'eventId': eventId,
      'sessionId': sessionId,
      'startTime': existingData['startTime'] ?? Timestamp.fromDate(now),
      'endTime': null,
      'totalWords': vocabList.length,
      'cardDwellTimes': existingData['cardDwellTimes'] ?? Map.fromIterables(
        List.generate(vocabList.length, (i) => i.toString()),
        List.filled(vocabList.length, 0), // 初始停留时间为0
      ),
      'totalLearningTime': existingData['totalLearningTime'] ?? 0,
      'leaveCount': existingData['leaveCount'] ?? 0, // 离开次数
      'status': 'learning', // learning, completed（不再記錄 quiz 狀態）
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  /// 完成詞彙學習會話（不經過測驗記錄）
  Future<void> completeLearningSession({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getVocabDataRef(uid, eventId);
      final now = DateTime.now();
      await ref.set({
        'status': 'completed',
        'endTime': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    } catch (e) {
      print('完成詞彙學習會話記錄失敗: $e');
    }
  }

  /// 记录卡片停留时间
  Future<void> recordCardDwellTime({
    required String uid,
    required String eventId,
    required int cardIndex,
    required int dwellTimeMs,
  }) async {
    try {
      final ref = await _getVocabDataRef(uid, eventId);

      final snap = await ref.get();
      if (snap.exists) {
        // 更新卡片停留时间
        await ref.update({
          'cardDwellTimes.$cardIndex': FieldValue.increment(dwellTimeMs),
          'totalLearningTime': FieldValue.increment(dwellTimeMs),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      } else {
        // 文檔不存在時先建檔
        await ref.set({
          'eventId': eventId,
          'cardDwellTimes': {cardIndex.toString(): dwellTimeMs},
          'totalLearningTime': dwellTimeMs,
          'leaveCount': 0,
          'status': 'learning',
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('記錄卡片停留時間失敗: $e');
    }
  }

  /// 记录离开学习页面
  Future<void> recordLeaveSession({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getVocabDataRef(uid, eventId);

      final snap = await ref.get();
      if (snap.exists) {
        // 增加离开次数
        await ref.update({
          'leaveCount': FieldValue.increment(1),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      } else {
        // 文檔不存在時先建檔
        await ref.set({
          'eventId': eventId,
          'leaveCount': 1,
          'status': 'learning',
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        }, SetOptions(merge: true));
      }
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
      final ref = await _getVocabDataRef(uid, eventId);
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
      final ref = await _getVocabDataRef(uid, eventId);
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

  /// 获取词汇学习会话数据
  Future<Map<String, dynamic>?> getVocabSessionData({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getVocabDataRef(uid, eventId);
      final doc = await ref.get();
      
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('獲取詞彙學習會話數據失敗: $e');
      return null;
    }
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
            final vocabRef = eventDoc.reference.collection('vocab').doc('analytics');
            final vocabDoc = await vocabRef.get();
            
            if (vocabDoc.exists) {
              final data = vocabDoc.data()! as Map<String, dynamic>;
              final startTime = data['startTime'] as Timestamp?;
              
              // 检查时间范围
              if (startDate != null && startTime != null && startTime.toDate().isBefore(startDate)) {
                continue;
              }
              if (endDate != null && startTime != null && startTime.toDate().isAfter(endDate)) {
                continue;
              }
              
              // 只统计已完成的会话
              if (data['status'] == 'completed') {
                totalSessions++;
                totalLearningTime += (data['totalLearningTime'] as num?)?.toInt() ?? 0;
                // 不再累加 quiz 資訊

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