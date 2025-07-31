import 'package:cloud_firestore/cloud_firestore.dart';

/// 每日报告数据模型
class DailyReportModel {
  final String id;
  final String uid;
  final DateTime date; // 报告日期
  final String group; // 新增：实验组或对照组
  
  // 1. 今日延遲的任務有哪些？（勾選）
  final List<String> delayedTaskIds; // 被延迟的任务ID列表
  final List<String> delayReasons; // 延迟原因（多选）
  final String? delayOtherReason; // 其他原因
  
  // 1.5. 今天開始但沒有完成任務的原因？（簡答）
  final String? incompleteReason; // 开始但未完成任务的原因
  
  // 2. 對今天自己執行任務的表現的感受（1-5）
  final int overallSatisfaction;
  
  // 3. 回顧今天的任務，明天還想不想開始（簡答）
  final String? tomorrowMotivation;
  
  // 4. 今天有沒有跟Coach聊天？（是非）
  final bool hadChatWithCoach;
  
  // 5. Coach聊天的幫助？（1-5分）（如果第4題為是才顯示）
  final int? coachHelpRating;
  
  // 6. 今天為什麼沒有跟Coach聊天？（如果第4題為否才顯示）
  final List<String> noChatReasons;
  final String? noChatOtherReason;
  
  // 7. 今日AI Coach聊一聊有什麼幫助？（如果第4題為是才顯示）
  final List<String> chatHelpfulness;
  final String? chatOtherHelp;
  
  // 8. 你明天還想再開始任務前跟ai聊嗎（如果第4題為是才顯示）
  final bool? wantChatTomorrow;
  
  // 9. 可以改進的話希望ai可以改變什麼（如果第4題為是才顯示）
  final String? aiImprovementSuggestions;
  
  // 10. 有什麼狀況或心得與任務有關想紀錄？（簡答）
  final String? notes;
  
  // 明天最有可能延遲的任務（保留原有功能）
  final List<String> likelyDelayedTaskIds;
  
  final DateTime createdAt;
  final DateTime? updatedAt;

  DailyReportModel({
    required this.id,
    required this.uid,
    required this.date,
    required this.group, // 新增必需字段
    required this.delayedTaskIds,
    required this.delayReasons,
    this.delayOtherReason,
    this.incompleteReason,
    required this.overallSatisfaction,
    this.tomorrowMotivation,
    required this.hadChatWithCoach,
    this.coachHelpRating,
    required this.noChatReasons,
    this.noChatOtherReason,
    required this.chatHelpfulness,
    this.chatOtherHelp,
    this.wantChatTomorrow,
    this.aiImprovementSuggestions,
    this.notes,
    required this.likelyDelayedTaskIds,
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
      delayedTaskIds: List<String>.from(data['delayedTaskIds'] ?? []),
      delayReasons: List<String>.from(data['delayReasons'] ?? []),
      delayOtherReason: data['delayOtherReason'],
      incompleteReason: data['incompleteReason'],
      overallSatisfaction: data['overallSatisfaction'] ?? 1,
      tomorrowMotivation: data['tomorrowMotivation'],
      hadChatWithCoach: data['hadChatWithCoach'] ?? false,
      coachHelpRating: data['coachHelpRating'],
      noChatReasons: List<String>.from(data['noChatReasons'] ?? []),
      noChatOtherReason: data['noChatOtherReason'],
      chatHelpfulness: List<String>.from(data['chatHelpfulness'] ?? []),
      chatOtherHelp: data['chatOtherHelp'],
      wantChatTomorrow: data['wantChatTomorrow'],
      aiImprovementSuggestions: data['aiImprovementSuggestions'],
      notes: data['notes'],
      likelyDelayedTaskIds: List<String>.from(data['likelyDelayedTaskIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'date': Timestamp.fromDate(date),
      'group': group, // 新增字段
      'delayedTaskIds': delayedTaskIds,
      'delayReasons': delayReasons,
      if (delayOtherReason != null) 'delayOtherReason': delayOtherReason,
      if (incompleteReason != null) 'incompleteReason': incompleteReason,
      'overallSatisfaction': overallSatisfaction,
      if (tomorrowMotivation != null) 'tomorrowMotivation': tomorrowMotivation,
      'hadChatWithCoach': hadChatWithCoach,
      if (coachHelpRating != null) 'coachHelpRating': coachHelpRating,
      'noChatReasons': noChatReasons,
      if (noChatOtherReason != null) 'noChatOtherReason': noChatOtherReason,
      'chatHelpfulness': chatHelpfulness,
      if (chatOtherHelp != null) 'chatOtherHelp': chatOtherHelp,
      if (wantChatTomorrow != null) 'wantChatTomorrow': wantChatTomorrow,
      if (aiImprovementSuggestions != null) 'aiImprovementSuggestions': aiImprovementSuggestions,
      if (notes != null) 'notes': notes,
      'likelyDelayedTaskIds': likelyDelayedTaskIds,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  DailyReportModel copyWith({
    String? id,
    String? uid,
    DateTime? date,
    String? group,
    List<String>? delayedTaskIds,
    List<String>? delayReasons,
    String? delayOtherReason,
    String? incompleteReason,
    int? overallSatisfaction,
    String? tomorrowMotivation,
    bool? hadChatWithCoach,
    int? coachHelpRating,
    List<String>? noChatReasons,
    String? noChatOtherReason,
    List<String>? chatHelpfulness,
    String? chatOtherHelp,
    bool? wantChatTomorrow,
    String? aiImprovementSuggestions,
    String? notes,
    List<String>? likelyDelayedTaskIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DailyReportModel(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      date: date ?? this.date,
      group: group ?? this.group,
      delayedTaskIds: delayedTaskIds ?? this.delayedTaskIds,
      delayReasons: delayReasons ?? this.delayReasons,
      delayOtherReason: delayOtherReason ?? this.delayOtherReason,
      incompleteReason: incompleteReason ?? this.incompleteReason,
      overallSatisfaction: overallSatisfaction ?? this.overallSatisfaction,
      tomorrowMotivation: tomorrowMotivation ?? this.tomorrowMotivation,
      hadChatWithCoach: hadChatWithCoach ?? this.hadChatWithCoach,
      coachHelpRating: coachHelpRating ?? this.coachHelpRating,
      noChatReasons: noChatReasons ?? this.noChatReasons,
      noChatOtherReason: noChatOtherReason ?? this.noChatOtherReason,
      chatHelpfulness: chatHelpfulness ?? this.chatHelpfulness,
      chatOtherHelp: chatOtherHelp ?? this.chatOtherHelp,
      wantChatTomorrow: wantChatTomorrow ?? this.wantChatTomorrow,
      aiImprovementSuggestions: aiImprovementSuggestions ?? this.aiImprovementSuggestions,
      notes: notes ?? this.notes,
      likelyDelayedTaskIds: likelyDelayedTaskIds ?? this.likelyDelayedTaskIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
} 