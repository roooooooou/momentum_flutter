import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/reading_content_model.dart';
import 'data_path_service.dart';
import 'day_number_service.dart';

class ReadingAnalyticsService {
  static final ReadingAnalyticsService _instance = ReadingAnalyticsService._internal();
  factory ReadingAnalyticsService() => _instance;
  ReadingAnalyticsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 获取阅读数据文档引用（自動解析事件所在集合）
  Future<DocumentReference> _getReadingDataRef(String uid, String eventId) async {
    final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
    return eventDoc.collection('reading').doc('analytics');
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

  /// 开始阅读会话
  Future<void> startReadingSession({
    required String uid,
    required String eventId,
    required List<ReadingContent> contents,
  }) async {
    final now = DateTime.now();
    final sessionId = 'reading_${eventId}_${now.millisecondsSinceEpoch}';
    final ref = await _getReadingDataRef(uid, eventId);
    
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
      'totalCards': contents.length,
      'cardDwellTimes': existingData['cardDwellTimes'] ?? Map.fromIterables(
        List.generate(contents.length, (i) => i.toString()),
        List.filled(contents.length, 0), // 初始停留时间为0
      ),
      'totalReadingTime': existingData['totalReadingTime'] ?? 0,
      'leaveCount': existingData['leaveCount'] ?? 0, // 离开次数
      'quizTime': 0,
      'quizCorrectAnswers': 0,
      'quizTotalQuestions': contents.length,
      'status': 'reading', // reading, quiz, completed
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
      final ref = await _getReadingDataRef(uid, eventId);
      
      // 检查文档是否存在
      final doc = await ref.get();
      if (doc.exists) {
        // 文档存在，更新卡片停留时间
        await ref.update({
          'cardDwellTimes.$cardIndex': FieldValue.increment(dwellTimeMs),
          'totalReadingTime': FieldValue.increment(dwellTimeMs),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      } else {
        // 文档不存在，创建新文档
        await ref.set({
          'eventId': eventId,
          'cardDwellTimes': {cardIndex.toString(): dwellTimeMs},
          'totalReadingTime': dwellTimeMs,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
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
      final ref = await _getReadingDataRef(uid, eventId);
      
      // 检查文档是否存在
      final doc = await ref.get();
      if (doc.exists) {
        // 文档存在，更新离开次数
        await ref.update({
          'leaveCount': FieldValue.increment(1),
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      } else {
        // 文档不存在，创建新文档
        await ref.set({
          'eventId': eventId,
          'leaveCount': 1,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      }
    } catch (e) {
      print('記錄離開學習頁面失敗: $e');
    }
  }

  /// 开始测验
  Future<void> startQuiz({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getReadingDataRef(uid, eventId);
      final now = DateTime.now();
      
      // 使用 set merge: true 確保文檔存在
      await ref.set({
        'eventId': eventId,
        'status': 'quiz',
        'quizStartTime': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    } catch (e) {
      print('开始测验记录失败: $e');
    }
  }

  /// 完成测验
  Future<void> completeQuiz({
    required String uid,
    required String eventId,
    required int correctAnswers,
    required int totalQuestions,
    int? quizTimeMs, // 新增測驗時間參數
  }) async {
    try {
      final ref = await _getReadingDataRef(uid, eventId);
      final now = DateTime.now();
      
      // 使用傳入的測驗時間，或從 Firestore 計算
      int finalQuizTimeMs = quizTimeMs ?? 0;
      if (finalQuizTimeMs == 0) {
        // 回退：從 Firestore 計算測驗時間
        final doc = await ref.get();
        if (doc.exists) {
          final data = doc.data()! as Map<String, dynamic>;
          final quizStartTime = data['quizStartTime'] as Timestamp?;
          if (quizStartTime != null) {
            finalQuizTimeMs = now.difference(quizStartTime.toDate()).inMilliseconds;
          }
        }
      }
      
      // 使用 set merge: true 確保文檔存在
      await ref.set({
        'eventId': eventId,
        'status': 'completed',
        'endTime': Timestamp.fromDate(now),
        'quizTime': finalQuizTimeMs,
        'quizCorrectAnswers': correctAnswers,
        'quizTotalQuestions': totalQuestions,
        'quizScore': totalQuestions > 0 ? (correctAnswers / totalQuestions * 100).round() : 0,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      // 儲存測驗結果到簡化路徑：users/{uid}/quiz/reading_w{week}
      final week = await _computeWeekFromEvent(uid, eventId);
      final quizId = 'reading_w$week'; // 與 vocab 統一：以週為單位
      
      final quizDocRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('quiz')
          .doc(quizId);
      
      // 直接儲存到 quiz 集合，不使用 attempts 子集合
      await quizDocRef.set({
        'type': 'reading',
        'eventId': eventId,
        'week': week,
        'correctAnswers': correctAnswers,
        'totalQuestions': totalQuestions,
        'score': totalQuestions > 0 ? (correctAnswers / totalQuestions * 100).round() : 0,
        'quizTimeMs': finalQuizTimeMs, // 新增測驗時間（毫秒）
        'savedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    } catch (e) {
      print('完成测验记录失败: $e');
    }
  }

  /// 完成閱讀會話（不經測驗亦可完結）
  Future<void> completeReadingSession({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getReadingDataRef(uid, eventId);
      final now = DateTime.now();
      await ref.set({
        'status': 'completed',
        'endTime': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    } catch (e) {
      print('完成閱讀會話記錄失敗: $e');
    }
  }

  /// 获取阅读会话数据
  Future<Map<String, dynamic>?> getReadingSessionData({
    required String uid,
    required String eventId,
  }) async {
    try {
      final ref = await _getReadingDataRef(uid, eventId);
      final doc = await ref.get();
      
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('获取阅读会话数据失败: $e');
      return null;
    }
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
            final readingRef = eventDoc.reference.collection('reading').doc('analytics');
            final readingDoc = await readingRef.get();
            
                         if (readingDoc.exists) {
               final data = readingDoc.data()! as Map<String, dynamic>;
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
                 totalReadingTime += (data['totalReadingTime'] as num?)?.toInt() ?? 0;
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
            print('处理事件 ${eventDoc.id} 的阅读数据时出错: $e');
            continue;
          }
        }
      }

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