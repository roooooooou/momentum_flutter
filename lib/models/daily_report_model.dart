import 'package:cloud_firestore/cloud_firestore.dart';

/// 每日报告数据模型
class DailyReportModel {
  final String id;
  final String uid;
  final DateTime date; // 报告日期
  
  // 1. 今日被延遲的任務
  final List<String> delayedTaskIds; // 被延迟的任务ID列表
  final List<String> delayReasons; // 延迟原因（多选）
  final String? delayOtherReason; // 其他原因
  
  // 2. LLM 聊天介入帮助度
  final List<String> chatHelpfulness; // 聊天帮助度（多选）
  final String? chatOtherHelp; // 其他帮助
  
  // 3. 整体感受评分 (1-5)
  final int overallSatisfaction;
  
  // 4. AI 介入后任务感觉评分 (1-5)
  final int aiHelpRating;
  final bool noChatToday; // 今日沒有跟Coach聊天
  
  // 5. 明天最有可能延遲的任務
  final List<String> likelyDelayedTaskIds; // 明天可能延迟的任务ID
  
  // 6. 心得记录
  final String? notes; // 开放式记录
  
  final DateTime createdAt;
  final DateTime? updatedAt;

  DailyReportModel({
    required this.id,
    required this.uid,
    required this.date,
    required this.delayedTaskIds,
    required this.delayReasons,
    this.delayOtherReason,
    required this.chatHelpfulness,
    this.chatOtherHelp,
    required this.overallSatisfaction,
    required this.aiHelpRating,
    required this.noChatToday,
    required this.likelyDelayedTaskIds,
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
      delayedTaskIds: List<String>.from(data['delayedTaskIds'] ?? []),
      delayReasons: List<String>.from(data['delayReasons'] ?? []),
      delayOtherReason: data['delayOtherReason'],
      chatHelpfulness: List<String>.from(data['chatHelpfulness'] ?? []),
      chatOtherHelp: data['chatOtherHelp'],
      overallSatisfaction: data['overallSatisfaction'] ?? 1,
      aiHelpRating: data['aiHelpRating'] ?? 1,
      noChatToday: data['noChatToday'] ?? false,
      likelyDelayedTaskIds: List<String>.from(data['likelyDelayedTaskIds'] ?? []),
      notes: data['notes'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'date': Timestamp.fromDate(date),
      'delayedTaskIds': delayedTaskIds,
      'delayReasons': delayReasons,
      if (delayOtherReason != null) 'delayOtherReason': delayOtherReason,
      'chatHelpfulness': chatHelpfulness,
      if (chatOtherHelp != null) 'chatOtherHelp': chatOtherHelp,
      'overallSatisfaction': overallSatisfaction,
      'aiHelpRating': aiHelpRating,
      'noChatToday': noChatToday,
      'likelyDelayedTaskIds': likelyDelayedTaskIds,
      if (notes != null) 'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  DailyReportModel copyWith({
    String? id,
    String? uid,
    DateTime? date,
    List<String>? delayedTaskIds,
    List<String>? delayReasons,
    String? delayOtherReason,
    List<String>? chatHelpfulness,
    String? chatOtherHelp,
    int? overallSatisfaction,
    int? aiHelpRating,
    bool? noChatToday,
    List<String>? likelyDelayedTaskIds,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DailyReportModel(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      date: date ?? this.date,
      delayedTaskIds: delayedTaskIds ?? this.delayedTaskIds,
      delayReasons: delayReasons ?? this.delayReasons,
      delayOtherReason: delayOtherReason ?? this.delayOtherReason,
      chatHelpfulness: chatHelpfulness ?? this.chatHelpfulness,
      chatOtherHelp: chatOtherHelp ?? this.chatOtherHelp,
      overallSatisfaction: overallSatisfaction ?? this.overallSatisfaction,
      aiHelpRating: aiHelpRating ?? this.aiHelpRating,
      noChatToday: noChatToday ?? this.noChatToday,
      likelyDelayedTaskIds: likelyDelayedTaskIds ?? this.likelyDelayedTaskIds,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
} 