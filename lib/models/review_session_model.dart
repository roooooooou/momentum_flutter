import 'package:cloud_firestore/cloud_firestore.dart';

/// 代表一個事件的單次複習會話。
class ReviewSessionModel {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMin;

  ReviewSessionModel({
    required this.id,
    required this.startTime,
    this.endTime,
    this.durationMin,
  });

  /// 從 Firestore 文檔創建 ReviewSessionModel 實例。
  factory ReviewSessionModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReviewSessionModel(
      id: doc.id,
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp?)?.toDate(),
      durationMin: data['durationMin'] as int?,
    );
  }

  /// 將 ReviewSessionModel 實例轉換為 Map 以便寫入 Firestore。
  Map<String, dynamic> toMap() {
    return {
      'startTime': Timestamp.fromDate(startTime),
      if (endTime != null) 'endTime': Timestamp.fromDate(endTime!),
      if (durationMin != null) 'durationMin': durationMin,
    };
  }
}
