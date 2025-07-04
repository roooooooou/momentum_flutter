import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'enums.dart';

class EventModel {
  final String id;
  final String title;
  final String? googleEventId;
  final String? googleCalendarId;
  
  // === 時間 ===
  final DateTime scheduledStartTime;  // Calendar / Tasks 給的原始時間
  final DateTime scheduledEndTime;
  final DateTime? actualStartTime;
  final DateTime? completedTime;
  
  // === 互動 ===
  final StartTrigger? startTrigger;     // enum:int 0-tap_notif 1-tap_card 2-chat 3-auto
  final String? chatId;                 // evt42_20250703T0130
  final List<String> notifIds;          // ["evt42-1st", "evt42-2nd"]
  
  // === 狀態 ===
  final TaskStatus? status;             // enum:int 0-NotStarted 1-InProgress 2-Completed 3-Overdue
  final int? startToOpenLatency;        // (actual - scheduled)/1000；預寫好省 ETL
  final bool isDone;

  // === meta ===
  final DateTime? createdAt;            // serverTimestamp
  final DateTime? updatedAt;            // serverTimestamp
  
  // === 原有字段 ===
  final DateTime? notifScheduledAt;

  EventModel({
    required this.id,
    required this.title,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
    required this.isDone,
    this.actualStartTime,
    this.completedTime,
    this.startTrigger,
    this.chatId,
    List<String>? notifIds,
    this.status,
    this.startToOpenLatency,
    this.createdAt,
    this.updatedAt,
    this.googleEventId,
    this.googleCalendarId,
    this.notifScheduledAt,
      }) : notifIds = notifIds ?? [];

  factory EventModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      title: d['title'],
      scheduledEndTime: (d['scheduledEndTime'] as Timestamp).toDate(),
      isDone: d['isDone'] ?? false,
      scheduledStartTime: (d['scheduledStartTime'] as Timestamp).toDate(),
      actualStartTime: (d['actualStartTime'] as Timestamp?)?.toDate(),
      completedTime: (d['completedTime'] as Timestamp?)?.toDate(),
      startTrigger: d['startTrigger'] != null ? StartTrigger.fromValue(d['startTrigger']) : null,
      chatId: d['chatId'],
      notifIds: d['notifIds'] != null ? List<String>.from(d['notifIds']) : [],
      status: d['status'] != null ? TaskStatus.fromValue(d['status']) : null,
      startToOpenLatency: d['startToOpenLatency'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      googleEventId: d['googleEventId'],
      googleCalendarId: d['googleCalendarId'],
      notifScheduledAt: (d['notifScheduledAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'isDone': isDone,
      'scheduledStartTime': Timestamp.fromDate(scheduledStartTime),
      'scheduledEndTime': Timestamp.fromDate(scheduledEndTime),
      if (actualStartTime != null) 'actualStartTime': Timestamp.fromDate(actualStartTime!),
      if (completedTime != null) 'completedTime': Timestamp.fromDate(completedTime!),
      if (startTrigger != null) 'startTrigger': startTrigger!.value,
      if (chatId != null) 'chatId': chatId,
      'notifIds': notifIds,
      if (status != null) 'status': status!.value,
      if (startToOpenLatency != null) 'startToOpenLatency': startToOpenLatency,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      if (googleEventId != null) 'googleEventId': googleEventId,
      if (googleCalendarId != null) 'googleCalendarId': googleCalendarId,
      if (notifScheduledAt != null) 'notifScheduledAt': Timestamp.fromDate(notifScheduledAt!),
    };
  }

  String get timeRange {
    final f = DateFormat('HH:mm');
    return '${f.format(scheduledStartTime.toLocal())} - ${f.format(scheduledEndTime.toLocal())}';
  }

  TaskStatus get computedStatus {
    // 如果有明確設定status，使用設定的值
    if (status != null) return status!;
    
    // 否則根據舊邏輯計算
    if (isDone) return TaskStatus.completed;
    if (actualStartTime != null) return TaskStatus.inProgress;
    if (DateTime.now().isAfter(scheduledStartTime)) return TaskStatus.overdue;
    return TaskStatus.notStarted;
  }

  EventModel copyWith({
    String? id,
    String? title,
    bool? isDone,
    DateTime? scheduledStartTime,
    DateTime? scheduledEndTime,
    DateTime? actualStartTime,
    DateTime? completedTime,
    StartTrigger? startTrigger,
    String? chatId,
    List<String>? notifIds,
    TaskStatus? status,
    int? startToOpenLatency,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? googleEventId,
    String? googleCalendarId,
    DateTime? notifScheduledAt,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      scheduledStartTime: scheduledStartTime ?? this.scheduledStartTime,
      scheduledEndTime: scheduledEndTime ?? this.scheduledEndTime,
      actualStartTime: actualStartTime ?? this.actualStartTime,
      completedTime: completedTime ?? this.completedTime,
      startTrigger: startTrigger ?? this.startTrigger,
      chatId: chatId ?? this.chatId,
      notifIds: notifIds ?? this.notifIds,
      status: status ?? this.status,
      startToOpenLatency: startToOpenLatency ?? this.startToOpenLatency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      googleEventId: googleEventId ?? this.googleEventId,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      notifScheduledAt: notifScheduledAt ?? this.notifScheduledAt,
    );
  }
}


/// 實驗數據收集工具類
class ExperimentEventHelper {
  static final _firestore = FirebaseFirestore.instance;

  /// 記錄事件開始（用於實驗數據收集）
  static Future<void> recordEventStart({
    required String uid,
    required String eventId,
    required StartTrigger startTrigger,
    String? chatId,
  }) async {
    final now = DateTime.now();
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId);

    // 獲取事件的預定開始時間來計算延遲
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()!;
    final scheduledStartTime = (data['scheduledStartTime'] as Timestamp).toDate();
    final latencySec = now.difference(scheduledStartTime).inSeconds;

    // 檢查是否已經有 startTrigger，如果有則保留原有的
    final existingStartTrigger = data['startTrigger'];
    final finalStartTrigger = existingStartTrigger ?? startTrigger.value;

    await ref.set({
      'actualStartTime': Timestamp.fromDate(now),
      'startTrigger': finalStartTrigger,
      'startToOpenLatency': latencySec,
      'status': TaskStatus.inProgress.value,
      'updatedAt': Timestamp.fromDate(now),
      'isDone': false,
      if (chatId != null) 'chatId': chatId,
    }, SetOptions(merge: true));
  }

  /// 記錄事件完成（用於實驗數據收集）
  static Future<void> recordEventCompletion({
    required String uid,
    required String eventId,
    String? chatId,
  }) async {
    final now = DateTime.now();
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId);

    await ref.set({
      'isDone': true,
      'completedTime': Timestamp.fromDate(now),
      'status': TaskStatus.completed.value,
      'updatedAt': Timestamp.fromDate(now),
      if (chatId != null) 'chatId': chatId,
    }, SetOptions(merge: true));
  }



  /// 記錄通知點擊（不開始任務，只記錄觸發源）
  static Future<void> recordNotificationTap({
    required String uid,
    required String eventId,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId);

    await ref.set({
      'startTrigger': StartTrigger.tapNotification.value,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  /// 記錄聊天觸發（不開始任務，只設置chatId和觸發源）
  static Future<void> recordChatTrigger({
    required String uid,
    required String eventId,
    required String chatId,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId);

    await ref.set({
      'chatId': chatId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  /// 設置聊天ID
  static Future<void> setChatId({
    required String uid,
    required String eventId,
    required String chatId,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId);

    await ref.set({
      'chatId': chatId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  /// 更新事件狀態（用於實驗數據收集）
  static Future<void> updateEventStatus({
    required String uid,
    required String eventId,
    required TaskStatus status,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId);

    await ref.set({
      'status': status.value,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  /// 生成聊天ID（格式：eventId_yyyyMMddTHHmm）
  static String generateChatId(String eventId, DateTime timestamp) {
    final formattedTime = timestamp
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:\-.]'), '')
        .substring(0, 13); // yyyyMMddTHHmm
    return '${eventId}_$formattedTime';
  }

  /// 記錄通知發送成功（實驗數據收集）
  static Future<void> recordNotificationDelivered({
    required String uid,
    required String eventId,
    required String notifId,
  }) async {
    final now = DateTime.now();
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId)
        .collection('notifications')
        .doc(notifId);

    await ref.set({
      'delivered_time': Timestamp.fromDate(now),
      'opened_time': null,
      'result': NotificationResult.dismiss.value,
      'snooze_minutes': null,
      'latency_sec': null,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// 記錄通知被點擊打開（實驗數據收集）
  static Future<void> recordNotificationOpened({
    required String uid,
    required String eventId,
    required String notifId,
  }) async {
    final now = DateTime.now();
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId)
        .collection('notifications')
        .doc(notifId);

    // 獲取已存在的數據來計算延遲
    final snap = await ref.get();
    if (snap.exists) {
      final data = snap.data()!;
      final deliveredTime = (data['delivered_time'] as Timestamp?)?.toDate();
      final latencySec = deliveredTime != null 
          ? now.difference(deliveredTime).inSeconds 
          : null;

      await ref.update({
        'opened_time': Timestamp.fromDate(now),
        'latency_sec': latencySec,
      });
    }
  }

  /// 記錄通知操作結果（實驗數據收集）
  static Future<void> recordNotificationResult({
    required String uid,
    required String eventId,
    required String notifId,
    required NotificationResult result,
    int? snoozeMinutes,
  }) async {
    final ref = _firestore
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(eventId)
        .collection('notifications')
        .doc(notifId);

    final updateData = <String, dynamic>{
      'result': result.value,
    };

    if (result == NotificationResult.snooze && snoozeMinutes != null) {
      updateData['snooze_minutes'] = snoozeMinutes;
    }

    await ref.update(updateData);
  }
}

/// 通知實驗數據模型
class NotificationData {
  final String id;                    // 通知ID
  final DateTime? deliveredTime;      // 發送成功時間
  final DateTime? openedTime;         // 用戶點擊時間
  final NotificationResult? result;   // 操作結果
  final int? snoozeMinutes;          // 延後分鐘數
  final int? latencySec;             // 延遲秒數
  final DateTime? createdAt;         // 創建時間

  NotificationData({
    required this.id,
    this.deliveredTime,
    this.openedTime,
    this.result,
    this.snoozeMinutes,
    this.latencySec,
    this.createdAt,
  });

  factory NotificationData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return NotificationData(
      id: doc.id,
      deliveredTime: (data['delivered_time'] as Timestamp?)?.toDate(),
      openedTime: (data['opened_time'] as Timestamp?)?.toDate(),
      result: data['result'] != null 
          ? NotificationResult.fromValue(data['result']) 
          : null,
      snoozeMinutes: data['snooze_minutes'],
      latencySec: data['latency_sec'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (deliveredTime != null) 'delivered_time': Timestamp.fromDate(deliveredTime!),
      if (openedTime != null) 'opened_time': Timestamp.fromDate(openedTime!),
      if (result != null) 'result': result!.value,
      if (snoozeMinutes != null) 'snooze_minutes': snoozeMinutes,
      if (latencySec != null) 'latency_sec': latencySec,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
    };
  }
} 
