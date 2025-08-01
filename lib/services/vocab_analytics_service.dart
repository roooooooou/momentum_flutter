import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vocab_content_model.dart';
import 'data_path_service.dart';

class VocabAnalyticsService {
  static final VocabAnalyticsService _instance = VocabAnalyticsService._internal();
  factory VocabAnalyticsService() => _instance;
  VocabAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 获取词汇数据文档引用
  Future<DocumentReference> _getVocabDataRef(String uid, String eventId) async {
    final now = DateTime.now();
    final group = await DataPathService.instance.getDateGroupName(uid, now);
    final eventsCollection = await DataPathService.instance.getEventsCollectionByGroup(uid, group);
    return eventsCollection.doc(eventId).collection('vocab').doc('analytics');
  }

  /// 开始词汇学习会话
  Future<void> startVocabSession({
    required String uid,
    required String eventId,
    required List<VocabContent> vocabList,
  }) async {
    final now = DateTime.now();
    final sessionId = 'vocab_${eventId}_${now.millisecondsSinceEpoch}';
    final ref = await _getVocabDataRef(uid, eventId);
    
    await ref.set({
      'eventId': eventId,
      'sessionId': sessionId,
      'startTime': Timestamp.fromDate(now),
      'endTime': null,
      'totalWords': vocabList.length,
      'cardDwellTimes': Map.fromIterables(
        List.generate(vocabList.length, (i) => i.toString()),
        List.filled(vocabList.length, 0), // 初始停留时间为0
      ),
      'totalLearningTime': 0,
      'quizTime': 0,
      'quizCorrectAnswers': 0,
      'quizTotalQuestions': 5, // 固定5题测验
      'status': 'learning', // learning, quiz, completed
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
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
      
      // 更新卡片停留时间
      await ref.update({
        'cardDwellTimes.$cardIndex': FieldValue.increment(dwellTimeMs),
        'totalLearningTime': FieldValue.increment(dwellTimeMs),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      print('記錄卡片停留時間失敗: $e');
    }
  }

  /// 开始测验
  Future<void> startQuiz({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getVocabDataRef(uid, eventId);
      final now = DateTime.now();
      
      await ref.update({
        'status': 'quiz',
        'quizStartTime': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
    } catch (e) {
      print('開始測驗記錄失敗: $e');
    }
  }

  /// 完成测验
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
      int quizTimeMs = 0;
      if (doc.exists) {
        final data = doc.data()! as Map<String, dynamic>;
        final quizStartTime = data['quizStartTime'] as Timestamp?;
        if (quizStartTime != null) {
          quizTimeMs = now.difference(quizStartTime.toDate()).inMilliseconds;
        }
      }
      
      await ref.update({
        'status': 'completed',
        'endTime': Timestamp.fromDate(now),
        'quizTime': quizTimeMs,
        'quizCorrectAnswers': correctAnswers,
        'quizTotalQuestions': totalQuestions,
        'quizScore': totalQuestions > 0 ? (correctAnswers / totalQuestions * 100).round() : 0,
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

  /// 获取用户所有词汇学习统计
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
      int totalQuizTime = 0;
      int totalCorrectAnswers = 0;
      int totalQuestions = 0;
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
                totalQuizTime += (data['quizTime'] as num?)?.toInt() ?? 0;
                totalCorrectAnswers += (data['quizCorrectAnswers'] as num?)?.toInt() ?? 0;
                totalQuestions += (data['quizTotalQuestions'] as num?)?.toInt() ?? 0;

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
        'averageScore': totalQuestions > 0 ? (totalCorrectAnswers / totalQuestions * 100).round() : 0,
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