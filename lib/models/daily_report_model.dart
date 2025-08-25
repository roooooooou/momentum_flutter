import 'package:cloud_firestore/cloud_firestore.dart';

/// 每日报告数据模型
class DailyReportModel {
  final String id;
  final String uid;
  final DateTime date; // 报告日期
  final String group; // 新增：实验组或对照组
  
  // 1. 今天延遲任務的原因（多選）
  final List<String> delayReasons; // 延迟原因（多选）
  final String? delayOtherReason; // 其他原因
  
  // 2. 今天開始但沒有完成任務的原因？（多選）
  final List<String> incompleteReasons; // 开始但未完成任务的原因（多选）
  final String? incompleteOtherReason; // 其他原因
  
  // 3. 今天的文章閱讀對我來說是有趣、有幫助的（1-5）
  final int readingHelpfulness;
  
  // 4. 完成今天單字任務對我**學業**有幫助（1-5）
  final int vocabHelpfulness;
  
  // 5. 對今天自己學習的表現的感受（1-5分）
  final int overallSatisfaction;
  
  // 6. 我有能力在預定時間內完成明天的學習任務（1-5分）
  final int tomorrowConfidence;
  
  // 7. 有什麼狀況或心得與任務有關想紀錄（突發事件，系統錯誤…）？（簡答）
  final String? notes;
  
  final DateTime createdAt;
  final DateTime? updatedAt;

  DailyReportModel({
    required this.id,
    required this.uid,
    required this.date,
    required this.group, // 新增必需字段
    required this.delayReasons,
    this.delayOtherReason,
    required this.incompleteReasons,
    this.incompleteOtherReason,
    required this.readingHelpfulness,
    required this.vocabHelpfulness,
    required this.overallSatisfaction,
    required this.tomorrowConfidence,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  factory DailyReportModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return DailyReportModel(
      id: doc.id,
      uid: data['uid'],
      date: (data['date'] as Timestamp).toDate(),
      group: data['group'] ?? 'control', // 新增字段，默認為control
      delayReasons: List<String>.from(data['delayReasons'] ?? []),
      delayOtherReason: data['delayOtherReason'],
      incompleteReasons: List<String>.from(data['incompleteReasons'] ?? []),
      incompleteOtherReason: data['incompleteOtherReason'],
      readingHelpfulness: data['readingHelpfulness'] ?? 3,
      vocabHelpfulness: data['vocabHelpfulness'] ?? 3,
      overallSatisfaction: data['overallSatisfaction'] ?? 3,
      tomorrowConfidence: data['tomorrowConfidence'] ?? 3,
      notes: data['notes'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'date': Timestamp.fromDate(date),
      'group': group, // 新增字段
      'delayReasons': delayReasons,
      if (delayOtherReason != null) 'delayOtherReason': delayOtherReason,
      'incompleteReasons': incompleteReasons,
      if (incompleteOtherReason != null) 'incompleteOtherReason': incompleteOtherReason,
      'readingHelpfulness': readingHelpfulness,
      'vocabHelpfulness': vocabHelpfulness,
      'overallSatisfaction': overallSatisfaction,
      'tomorrowConfidence': tomorrowConfidence,
      if (notes != null) 'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  DailyReportModel copyWith({
    String? id,
    String? uid,
    DateTime? date,
    String? group,
    List<String>? delayReasons,
    String? delayOtherReason,
    List<String>? incompleteReasons,
    String? incompleteOtherReason,
    int? readingHelpfulness,
    int? vocabHelpfulness,
    int? overallSatisfaction,
    int? tomorrowConfidence,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DailyReportModel(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      date: date ?? this.date,
      group: group ?? this.group,
      delayReasons: delayReasons ?? this.delayReasons,
      delayOtherReason: delayOtherReason ?? this.delayOtherReason,
      incompleteReasons: incompleteReasons ?? this.incompleteReasons,
      incompleteOtherReason: incompleteOtherReason ?? this.incompleteOtherReason,
      readingHelpfulness: readingHelpfulness ?? this.readingHelpfulness,
      vocabHelpfulness: vocabHelpfulness ?? this.vocabHelpfulness,
      overallSatisfaction: overallSatisfaction ?? this.overallSatisfaction,
      tomorrowConfidence: tomorrowConfidence ?? this.tomorrowConfidence,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
} 