import 'package:cloud_firestore/cloud_firestore.dart';

/// 提供統一的測驗讀取介面，封裝 quiz 的路徑
class ExperimentQuizService {
  ExperimentQuizService._();
  static final instance = ExperimentQuizService._();

  final _firestore = FirebaseFirestore.instance;

  /// 獲取閱讀測驗資料
  Future<Map<String, dynamic>?> getReadingQuiz(String uid, {required int week}) async {
    final quizId = 'reading_w$week';
    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('quiz')
        .doc(quizId);
    final snap = await docRef.get();
    if (snap.exists) {
      final data = snap.data()!;
      data['quizId'] = snap.id;
      data['type'] = 'reading';
      data['week'] = week;
      return data;
    }
    return null;
  }

  /// 獲取詞彙測驗資料
  Future<Map<String, dynamic>?> getVocabQuiz(String uid, {required int week}) async {
    final quizId = 'vocab_w$week';
    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('quiz')
        .doc(quizId);
    final snap = await docRef.get();
    if (snap.exists) {
      final data = snap.data()!;
      data['quizId'] = snap.id;
      data['type'] = 'vocab';
      data['week'] = week;
      return data;
    }
    return null;
  }

  /// 獲取所有測驗資料（reading 和 vocab）
  Future<List<Map<String, dynamic>>> getAllQuizzes(String uid) async {
    final col = _firestore
        .collection('users')
        .doc(uid)
        .collection('quiz')
        .orderBy('savedAt', descending: true);
    final snap = await col.get();
    return snap.docs.map((d) {
      final data = d.data();
      data['quizId'] = d.id;
      return data;
    }).toList();
  }

  // 向後相容的方法名稱
  Future<Map<String, dynamic>?> getLatestReadingAttempt(String uid, int week) async {
    return await getReadingQuiz(uid, week: week);
  }

  Future<Map<String, dynamic>?> getLatestVocabAttempt(String uid, int week) async {
    return await getVocabQuiz(uid, week: week);
  }
}

