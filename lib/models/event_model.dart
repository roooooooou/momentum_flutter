import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'enums.dart';
import '../services/data_path_service.dart';
import '../services/notification_service.dart';

class EventModel {
  final String id;
  final String title;
  final String? description;  // 儲存但不在UI中顯示
  final String? googleEventId;
  final String? googleCalendarId;
  
  // === 時間 ===
  final DateTime scheduledStartTime;  // Calendar / Tasks 給的原始時間
  final DateTime scheduledEndTime;
  final DateTime? actualStartTime;
  final DateTime? completedTime;
  
  // === 數據收集 - 持續時間 ===
  final int? expectedDurationMin;      // 期望持續時間（分鐘）
  final int? actualDurationMin;        // 實際持續時間（分鐘）
  final int? pauseCount;               // 暫停次數
  final DateTime? pauseAt;             // 🎯 新增：暫停時間
  final DateTime? resumeAt;            // 🎯 新增：繼續時間
  
  // === 複習統計 (新結構) ===
  final String? activeReviewSessionId; // 正在進行的複習會話ID

  // === 互動 ===
  final StartTrigger? startTrigger;     // enum:int 0-tap_notif 1-tap_card 2-chat 3-auto
  final String? chatId;                 // evt42_20250703T0130
  final List<String> notifIds;          // ["evt42-1st", "evt42-2nd"]
  
  // === 狀態 ===
  final TaskStatus? status;             // enum:int 0-NotStarted 1-InProgress 2-Completed 3-Overdue
  final int? startToOpenLatency;        // (actual - scheduled)/1000；預寫好省 ETL
  final bool isDone;

  // === 事件歷史記錄 ===
  final DateTime? archivedAt;                    // 归档时间（被删除/移动的时间）

  // === meta ===
  final DateTime? createdAt;            // serverTimestamp
  final DateTime? updatedAt;            // serverTimestamp
  
  // === 原有字段 ===
  final DateTime? notifScheduledAt;

  // === 新增字段 ===
  final DateTime date;                  // 事件日期（用於按日期分組）
  final int? dayNumber;                 // 相对于账号创建日期的天数

  EventModel({
    required this.id,
    required this.title,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
    required this.isDone,
    required this.date,                 // 新增必需字段
    this.description,
    this.actualStartTime,
    this.completedTime,
    this.startTrigger,
    this.chatId,
    List<String>? notifIds,
    this.status,
    this.startToOpenLatency,

    this.archivedAt,
    this.createdAt,
    this.updatedAt,
    this.googleEventId,
    this.googleCalendarId,
    this.notifScheduledAt,
    this.expectedDurationMin,
    this.actualDurationMin,
    this.pauseCount,
    this.pauseAt,
    this.resumeAt,
    this.activeReviewSessionId,
    this.dayNumber,
  }) : notifIds = notifIds ?? [];

  factory EventModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      title: d['title'],
      description: d['description'],
      scheduledEndTime: (d['scheduledEndTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDone: d['isDone'] ?? false,
      scheduledStartTime: (d['scheduledStartTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      date: (d['date'] as Timestamp?)?.toDate() ?? (d['scheduledStartTime'] as Timestamp?)?.toDate() ?? DateTime.now(), // 新增字段，如果沒有則使用 scheduledStartTime 或當前時間
      dayNumber: d['dayNumber'] is int ? d['dayNumber'] as int : (d['dayNumber'] is String ? int.tryParse(d['dayNumber'] as String) : null),
      actualStartTime: (d['actualStartTime'] as Timestamp?)?.toDate(),
      completedTime: (d['completedTime'] as Timestamp?)?.toDate(),
      startTrigger: d['startTrigger'] != null ? StartTrigger.fromValue(d['startTrigger'] is int ? d['startTrigger'] as int : (d['startTrigger'] is String ? int.tryParse(d['startTrigger'] as String) ?? 0 : 0)) : null,
      chatId: d['chatId'],
      notifIds: d['notifIds'] != null ? List<String>.from(d['notifIds']) : [],
      status: d['status'] != null ? TaskStatus.fromValue(d['status'] is int ? d['status'] as int : (d['status'] is String ? int.tryParse(d['status'] as String) ?? 0 : 0)) : null,
      startToOpenLatency: d['startToOpenLatency'] is int ? d['startToOpenLatency'] as int : (d['startToOpenLatency'] is String ? int.tryParse(d['startToOpenLatency'] as String) : null),

      archivedAt: (d['archivedAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      googleEventId: d['googleEventId'],
      googleCalendarId: d['googleCalendarId'],
              notifScheduledAt: (d['notifScheduledAt'] as Timestamp?)?.toDate(),
        expectedDurationMin: d['expectedDurationMin'] is int ? d['expectedDurationMin'] as int : (d['expectedDurationMin'] is String ? int.tryParse(d['expectedDurationMin'] as String) : null),
        actualDurationMin: d['actualDurationMin'] is int ? d['actualDurationMin'] as int : (d['actualDurationMin'] is String ? int.tryParse(d['actualDurationMin'] as String) : null),
        pauseCount: d['pauseCount'] is int ? d['pauseCount'] as int : (d['pauseCount'] is String ? int.tryParse(d['pauseCount'] as String) : null),
        pauseAt: (d['pauseAt'] as Timestamp?)?.toDate(),
        resumeAt: (d['resumeAt'] as Timestamp?)?.toDate(),
        activeReviewSessionId: d['activeReviewSessionId'] as String?,
      );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      if (description != null) 'description': description,
      'isDone': isDone,
      'scheduledStartTime': Timestamp.fromDate(scheduledStartTime),
      'scheduledEndTime': Timestamp.fromDate(scheduledEndTime),
      'date': Timestamp.fromDate(date), // 新增字段
      if (dayNumber != null) 'dayNumber': dayNumber,
      if (actualStartTime != null) 'actualStartTime': Timestamp.fromDate(actualStartTime!),
      if (completedTime != null) 'completedTime': Timestamp.fromDate(completedTime!),
      if (startTrigger != null) 'startTrigger': startTrigger!.value,
      if (chatId != null) 'chatId': chatId,
      'notifIds': notifIds,
      if (status != null) 'status': status!.value,
      if (startToOpenLatency != null) 'startToOpenLatency': startToOpenLatency,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      if (googleEventId != null) 'googleEventId': googleEventId,
      if (googleCalendarId != null) 'googleCalendarId': googleCalendarId,
      if (notifScheduledAt != null) 'notifScheduledAt': Timestamp.fromDate(notifScheduledAt!),
              if (expectedDurationMin != null) 'expectedDurationMin': expectedDurationMin,
        if (actualDurationMin != null) 'actualDurationMin': actualDurationMin,
        if (pauseCount != null) 'pauseCount': pauseCount,
        if (pauseAt != null) 'pauseAt': Timestamp.fromDate(pauseAt!),
        if (resumeAt != null) 'resumeAt': Timestamp.fromDate(resumeAt!),
        if (activeReviewSessionId != null) 'activeReviewSessionId': activeReviewSessionId,
      };
  }

  String get timeRange {
    final f = DateFormat('HH:mm');
    return '${f.format(scheduledStartTime.toLocal())} - ${f.format(scheduledEndTime.toLocal())}';
  }



  TaskStatus get computedStatus {
    // 如果有明確設定status，使用設定的值
    if (status != null) return status!;
    
    // 否則根據邏輯計算
    if (isDone) return TaskStatus.completed;
    
    final now = DateTime.now();
    
    // 如果任務已開始
    if (actualStartTime != null) {
      // 🎯 修复：正确处理暂停后继续的状态判断
      DateTime dynamicEndTime;
      
      if (pauseAt != null && resumeAt != null) {
        // 如果任务有暂停时间和继续时间，需要调整结束时间
        // 原定任务时长
        final originalTaskDuration = scheduledEndTime.difference(scheduledStartTime);
        // 已经工作的时间（从开始到暂停）
        final workedDuration = pauseAt!.difference(actualStartTime!);
        // 剩余工作时间
        final remainingWorkDuration = originalTaskDuration - workedDuration;
        // 调整后的结束时间 = 继续时间 + 剩余工作时间
        dynamicEndTime = resumeAt!.add(remainingWorkDuration);
      } else if (pauseAt != null) {
        // 如果只有暂停时间但没有继续时间（暂停状态）
        // 原定任务时长
        final originalTaskDuration = scheduledEndTime.difference(scheduledStartTime);
        // 已经工作的时间
        final workedDuration = pauseAt!.difference(actualStartTime!);
        // 剩余工作时间
        final remainingWorkDuration = originalTaskDuration - workedDuration;
        // 调整后的结束时间 = 当前时间 + 剩余工作时间
        dynamicEndTime = now.add(remainingWorkDuration);
      } else {
        // 没有暂停时间，使用原来的逻辑
        final taskDuration = scheduledEndTime.difference(scheduledStartTime);
        dynamicEndTime = actualStartTime!.add(taskDuration);
      }
      
      // 如果超過動態結束時間，返回超時狀態
      if (now.isAfter(dynamicEndTime)) {
        return TaskStatus.overtime;
      }
      
      // 否則返回進行中
      return TaskStatus.inProgress;
    }
    
    // 任務未開始，檢查是否逾期
    if (now.isAfter(scheduledStartTime)) return TaskStatus.overdue;
    
    // 未開始且未逾期
    return TaskStatus.notStarted;
  }

  EventModel copyWith({
    String? id,
    String? title,
    String? description,
    bool? isDone,
    DateTime? scheduledStartTime,
    DateTime? scheduledEndTime,
    DateTime? actualStartTime,
    DateTime? completedTime,
    DateTime? date,
    StartTrigger? startTrigger,
    String? chatId,
    List<String>? notifIds,
    TaskStatus? status,
    int? startToOpenLatency,

    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? googleEventId,
    String? googleCalendarId,
    DateTime? notifScheduledAt,
    int? expectedDurationMin,
    int? actualDurationMin,
    int? pauseCount,
    DateTime? pauseAt,
    DateTime? resumeAt,
    String? activeReviewSessionId,
    int? dayNumber,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isDone: isDone ?? this.isDone,
      scheduledStartTime: scheduledStartTime ?? this.scheduledStartTime,
      scheduledEndTime: scheduledEndTime ?? this.scheduledEndTime,
      actualStartTime: actualStartTime ?? this.actualStartTime,
      completedTime: completedTime ?? this.completedTime,
      date: date ?? this.date,
      startTrigger: startTrigger ?? this.startTrigger,
      chatId: chatId ?? this.chatId,
      notifIds: notifIds ?? this.notifIds,
      status: status ?? this.status,
      startToOpenLatency: startToOpenLatency ?? this.startToOpenLatency,

      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      googleEventId: googleEventId ?? this.googleEventId,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      notifScheduledAt: notifScheduledAt ?? this.notifScheduledAt,
      expectedDurationMin: expectedDurationMin ?? this.expectedDurationMin,
      actualDurationMin: actualDurationMin ?? this.actualDurationMin,
      pauseCount: pauseCount ?? this.pauseCount,
      pauseAt: pauseAt ?? this.pauseAt,
      resumeAt: resumeAt ?? this.resumeAt,
      activeReviewSessionId: activeReviewSessionId ?? this.activeReviewSessionId,
      dayNumber: dayNumber ?? this.dayNumber,
    );
  }
}


/// 實驗數據收集工具類
class ExperimentEventHelper {
  static final _firestore = FirebaseFirestore.instance;

  /// 获取用户事件文档引用（使用当前日期的数据路径）
  static Future<DocumentReference> _getEventRef(String uid, String eventId) async {
    // 統一委派給 DataPathService 處理（優先既有，再回退當日分組）
    return await DataPathService.instance.getEventDocAuto(uid, eventId);
  }

  /// 获取用户事件聊天文档引用（使用当前日期的数据路径）
  static Future<DocumentReference> _getChatRef(String uid, String eventId, String chatId) async {
    final eventDoc = await DataPathService.instance.getEventDocAuto(uid, eventId);
    return eventDoc.collection('chats').doc(chatId);
  }

  /// 記錄事件開始（用於實驗數據收集）
  static Future<void> recordEventStart({
    required String uid,
    required String eventId,
    required StartTrigger startTrigger,
    String? chatId,
  }) async {
    final now = DateTime.now();
    final ref = await _getEventRef(uid, eventId);

    // 獲取事件的預定開始時間來計算延遲
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data()! as Map<String, dynamic>;
    final scheduledStartTime = (data['scheduledStartTime'] as Timestamp).toDate();
    final latencySec = now.difference(scheduledStartTime).inSeconds;

    // 檢查是否已經有 startTrigger，如果有則保留原有的
    final existingStartTrigger = data['startTrigger'];
    final finalStartTrigger = existingStartTrigger ?? startTrigger.value;

    // 檢查是否已經有 actualStartTime，如果有則保留原有的
    final existingActualStartTime = data['actualStartTime'];
    
    await ref.set({
      if (existingActualStartTime == null) 'actualStartTime': Timestamp.fromDate(now),
      'startTrigger': finalStartTrigger,
      if (existingActualStartTime == null) 'startToOpenLatency': latencySec,
      'status': TaskStatus.inProgress.value,
      'updatedAt': Timestamp.fromDate(now),
      'isDone': false,
      'date': Timestamp.fromDate(now), // 添加日期字段
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
    final ref = await _getEventRef(uid, eventId);

    // 獲取事件數據以計算實際持續時間和期望持續時間
    final snap = await ref.get();
    int? actualDurationMin;
    int? expectedDurationMin;
    
    if (snap.exists) {
      final data = snap.data()! as Map<String, dynamic>;
      final actualStartTime = (data['actualStartTime'] as Timestamp?)?.toDate();
      final scheduledStartTime = (data['scheduledStartTime'] as Timestamp?)?.toDate();
      final scheduledEndTime = (data['scheduledEndTime'] as Timestamp?)?.toDate();
      
      // 計算實際持續時間（完成時間 - 實際開始時間）
      if (actualStartTime != null) {
        actualDurationMin = now.difference(actualStartTime).inMinutes;
      }
      
      // 計算期望持續時間（計劃結束時間 - 計劃開始時間）
      if (scheduledStartTime != null && scheduledEndTime != null) {
        expectedDurationMin = scheduledEndTime.difference(scheduledStartTime).inMinutes;
      }
    }

    await ref.set({
      'isDone': true,
      'completedTime': Timestamp.fromDate(now),
      'status': TaskStatus.completed.value,
      'updatedAt': Timestamp.fromDate(now),
      'date': Timestamp.fromDate(now), // 添加日期字段
      if (chatId != null) 'chatId': chatId,
      if (actualDurationMin != null) 'actualDurationMin': actualDurationMin,
      if (expectedDurationMin != null) 'expectedDurationMin': expectedDurationMin,
    }, SetOptions(merge: true));

    // 🎯 任務完成時取消所有相關通知並記錄為取消狀態
    // 注意：這裡沒有具體的通知ID，因為任務完成時所有通知都應該被取消
    await _cancelNotificationsAndRecordComplete(uid, eventId, snap.data() as Map<String, dynamic>?);
  }

  /// 任務完成時：只將未發送的通知標記為 cancel，已發送的通知保持原狀態
  /// 不會覆蓋已經有用戶互動記錄的通知
  static Future<void> _cancelNotificationsAndRecordComplete(String uid, String eventId, Map<String, dynamic>? eventData) async {
    try {
      if (eventData == null) return;

      final eventDate = eventData['date'] != null ? (eventData['date'] as Timestamp).toDate() : null;

      // 1. 處理第一個和第二個通知（如果存在notifIds）
      final notifIds = eventData['notifIds'] as List<dynamic>?;
      if (notifIds != null && notifIds.isNotEmpty) {
        for (final notifId in notifIds) {
          if (notifId is String) {
            // 計算通知ID並取消
            if (notifId.endsWith('-1st')) {
              final firstNotificationId = 1000 + (eventId.hashCode.abs() % 100000);
              await NotificationService.instance.cancelNotification(firstNotificationId);
              
              // 🎯 檢查通知是否已經有用戶互動，只有在未發送時才記錄為 cancel
              await _recordNotificationCompleteIfNotExists(uid, eventId, notifId, eventDate);
              
            } else if (notifId.endsWith('-2nd')) {
              final secondNotificationId = 1000 + (eventId.hashCode.abs() % 100000) + 1;
              await NotificationService.instance.cancelNotification(secondNotificationId);
              
              // 🎯 檢查通知是否已經有用戶互動，只有在未發送時才記錄為 cancel
              await _recordNotificationCompleteIfNotExists(uid, eventId, notifId, eventDate);
            }
          }
        }
      }

      if (kDebugMode) {
        print('🎯 任務完成：已取消事件 $eventId 的未發送通知並記錄為 cancel 狀態');
      }
    } catch (e) {
      if (kDebugMode) {
        print('取消通知並記錄完成狀態失敗: $e');
      }
    }
  }

  /// 🎯 [Corrected] 記錄第二個通知因為任務已開始而被取消
  static Future<void> recordSecondNotificationCancelled({
    required String uid,
    required String eventId,
    required DateTime eventDate,
  }) async {
    final notifId = '$eventId-2nd';
    // 直接調用 `_recordNotificationCompleteIfNotExists` 即可，
    // 因為它的邏輯是檢查文檔是否存在，如果不存在（代表未發送），則記錄為 cancel。
    // 這完全符合我們的需求。
    await _recordNotificationCompleteIfNotExists(uid, eventId, notifId, eventDate);
  }

  /// 開始複習：只更新主事件的 activeReviewSessionId（由具體的 AnalyticsService 創建 review 文檔）
  static Future<void> recordReviewStart({
    required String uid,
    required String eventId,
  }) async {
    final now = DateTime.now();
    final eventRef = await _getEventRef(uid, eventId);

    // 檢查是否已有正在進行的複習
    final eventSnap = await eventRef.get();
    if (eventSnap.exists) {
      final data = eventSnap.data() as Map<String, dynamic>?;
      if (data != null && data.containsKey('activeReviewSessionId') && data['activeReviewSessionId'] != null) {
        if (kDebugMode) {
          print('Review session already active. Skipping start.');
        }
        return; // 已有活動中的複習，不再重複開始
      }
    }

    // 標記複習已開始，但不創建 review 文檔（由 AnalyticsService 負責）
    await eventRef.set({
      'reviewStarted': true, // 標記複習已開始
      'updatedAt': Timestamp.fromDate(now),
      'date': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }

  /// 結束複習：清除主事件的 activeReviewSessionId（review 文檔的結束由 AnalyticsService 處理）
  static Future<void> recordReviewEnd({
    required String uid,
    required String eventId,
  }) async {
    final now = DateTime.now();
    final eventRef = await _getEventRef(uid, eventId);

    final eventSnap = await eventRef.get();
    if (!eventSnap.exists) return;

    final data = eventSnap.data()! as Map<String, dynamic>;
    final activeSessionId = data['activeReviewSessionId'] as String?;

    if (activeSessionId == null) {
      if (kDebugMode) {
        print('No active review session to end.');
      }
      return; // 沒有活動中的複習
    }

    final reviewSessionRef = eventRef.collection('review').doc(activeSessionId);
    final reviewSnap = await reviewSessionRef.get();

    if (!reviewSnap.exists) {
       if (kDebugMode) {
        print('Active review session document not found. Clearing activeReviewSessionId.');
      }
      // 如果文檔不存在，至少要清理主事件的狀態，避免卡死
      await eventRef.set({
        'activeReviewSessionId': null,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
      return;
    }

    // AnalyticsService 已經處理了 review 文檔的結束，這裡只需要清理主事件狀態
    await eventRef.set({
      'activeReviewSessionId': null,
      'reviewStarted': false, // 標記複習已結束
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));
  }



  /// 記錄通知點擊（不開始任務，只記錄觸發源）
  static Future<void> recordNotificationTap({
    required String uid,
    required String eventId,
    String? notifId,
  }) async {
    final ref = await _getEventRef(uid, eventId);

    // 🎯 修正：只設置觸發源，不設置任務狀態
    // 任務狀態將由 recordEventStart 設置
    await ref.set({
      'startTrigger': StartTrigger.tapNotification.value,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'date': Timestamp.fromDate(DateTime.now()), // 添加日期字段
    }, SetOptions(merge: true));

    // 🎯 如果有通知ID，記錄通知點擊狀態
    if (notifId != null) {
      // 獲取事件日期以記錄通知狀態
      final eventSnap = await ref.get();
      if (eventSnap.exists) {
        final eventData = eventSnap.data() as Map<String, dynamic>;
        final eventDate = eventData['date'] != null ? (eventData['date'] as Timestamp).toDate() : null;
        
        // 🎯 修正：不預設記錄為 start 狀態，因為任務可能還沒有開始
        // 通知結果將由實際的用戶操作決定
        await recordNotificationResult(
          uid: uid,
          eventId: eventId,
          notifId: notifId,
          result: NotificationResult.dismiss, // 預設為已查看但未採取行動
          eventDate: eventDate,
        );
      }
    }
  }

  /// 記錄聊天觸發（不開始任務，只設置chatId和觸發源）
  static Future<void> recordChatTrigger({
    required String uid,
    required String eventId,
    required String chatId,
  }) async {
    final ref = await _getEventRef(uid, eventId);

    await ref.set({
      'chatId': chatId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'date': Timestamp.fromDate(DateTime.now()), // 添加日期字段
    }, SetOptions(merge: true));
  }

  /// 設置聊天ID
  static Future<void> setChatId({
    required String uid,
    required String eventId,
    required String chatId,
  }) async {
    final ref = await _getEventRef(uid, eventId);

    await ref.set({
      'chatId': chatId,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'date': Timestamp.fromDate(DateTime.now()), // 添加日期字段
    }, SetOptions(merge: true));
  }

  /// 更新事件狀態（用於實驗數據收集）
  static Future<void> updateEventStatus({
    required String uid,
    required String eventId,
    required TaskStatus status,
  }) async {
    final ref = await _getEventRef(uid, eventId);

    await ref.set({
      'status': status.value,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'date': Timestamp.fromDate(DateTime.now()), // 添加日期字段
    }, SetOptions(merge: true));
  }

  /// 生成聊天ID（格式：eventId_yyyyMMddTHHmm）
  static String generateChatId(String eventId, DateTime timestamp) {
    // 使用台灣時區格式化時間
    final taiwanTime = timestamp.toLocal(); // 確保使用本地時區（台灣時區）
    final formattedTime = taiwanTime
        .toIso8601String()
        .replaceAll(RegExp(r'[:\-.]'), '')
        .substring(0, 13); // yyyyMMddTHHmm
    return '${eventId}_$formattedTime';
  }

  /// 記錄通知排程（實驗數據收集）
  static Future<void> recordNotificationScheduled({
    required String uid,
    required String eventId,
    required String notifId,
    DateTime? scheduledTime,
    DateTime? eventDate, // 🎯 新增：事件发生的日期
  }) async {
    try {
      // 🎯 修复：根据事件发生的日期获取正确的通知文档路径
      DocumentReference ref;
      if (eventDate != null) {
        ref = await DataPathService.instance.getDateEventNotificationDoc(uid, eventId, notifId, eventDate);
        debugPrint('🎯 使用事件日期获取通知文档路径: eventDate=$eventDate');
      } else {
        ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);
        debugPrint('🎯 使用当前日期获取通知文档路径');
      }

      await ref.set({
        'opened_time': null,
        'notification_scheduled_time': scheduledTime != null ? Timestamp.fromDate(scheduledTime) : null,
        'result': NotificationResult.dismiss.value,
        'notif_to_click_sec': null,
        'created_at': FieldValue.serverTimestamp(),
      });
      
      // 🎯 調試：確認記錄成功
      debugPrint('通知排程記錄創建成功: notifId=$notifId, scheduledTime=$scheduledTime, eventDate=$eventDate');
    } catch (e) {
      // 🎯 調試：輸出錯誤信息
      debugPrint('記錄通知排程失敗: notifId=$notifId, error=$e');
      rethrow;
    }
  }

  /// 記錄通知發送成功（實驗數據收集）
  static Future<void> recordNotificationDelivered({
    required String uid,
    required String eventId,
    required String notifId,
    DateTime? eventDate, // 🎯 新增：事件发生的日期
  }) async {
    try {
      final now = DateTime.now();
      
      // 🎯 修复：根据事件发生的日期获取正确的通知文档路径
      DocumentReference ref;
      if (eventDate != null) {
        ref = await DataPathService.instance.getDateEventNotificationDoc(uid, eventId, notifId, eventDate);
        debugPrint('🎯 使用事件日期获取通知文档路径: eventDate=$eventDate');
      } else {
        ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);
        debugPrint('🎯 使用当前日期获取通知文档路径');
      }
      // 若文檔存在則更新，否則建立
      final snap = await ref.get();
      if (snap.exists) {
        // 文檔已存在，不需要更新任何字段
        return;
      } else {
        await ref.set({
          'opened_time': null,
          'notification_scheduled_time': null,
          'result': NotificationResult.dismiss.value,
          'notif_to_click_sec': null,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      
      // 🎯 調試：確認記錄成功
      debugPrint('通知發送記錄更新成功: notifId=$notifId, deliveredTime=$now, eventDate=$eventDate');
    } catch (e) {
      // 🎯 調試：輸出錯誤信息
      debugPrint('記錄通知發送失敗: notifId=$notifId, error=$e');
      rethrow;
    }
  }

  /// 記錄通知被點擊打開（實驗數據收集）
  static Future<void> recordNotificationOpened({
    required String uid,
    required String eventId,
    required String notifId,
    DateTime? eventDate, // 🎯 新增：事件发生的日期
  }) async {
    final now = DateTime.now();
    
    // 🎯 修复：根据事件发生的日期获取正确的通知文档路径
    DocumentReference ref;
    if (eventDate != null) {
      ref = await DataPathService.instance.getDateEventNotificationDoc(uid, eventId, notifId, eventDate);
    } else {
      ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);
    }

    try {
      // 獲取已存在的數據來計算延遲
      final snap = await ref.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        // 🎯 新增：計算從通知發送到點擊的時間
        // 使用 notification_scheduled_time 作為參考時間點
        final scheduledTime = (data['notification_scheduled_time'] as Timestamp?)?.toDate();
        final notifToClickSec = scheduledTime != null 
            ? now.difference(scheduledTime).inSeconds 
            : null;

        await ref.update({
          'opened_time': Timestamp.fromDate(now),
          'notif_to_click_sec': notifToClickSec, // 記錄通知發送到點擊的秒數
        });
      } else {
        // 🎯 修復：如果文档不存在，创建一个新文档
        await ref.set({
          'opened_time': Timestamp.fromDate(now),
          'notification_scheduled_time': null, // 沒有排程記錄
          'result': NotificationResult.dismiss.value,
          'notif_to_click_sec': null, // 无法计算延迟
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // 🎯 調試：輸出錯誤信息
      debugPrint('記錄通知打開失敗: notifId=$notifId, error=$e');
      rethrow;
    }
  }

  /// 記錄通知操作結果（實驗數據收集）
  static Future<void> recordNotificationResult({
    required String uid,
    required String eventId,
    required String notifId,
    required NotificationResult result,
    DateTime? eventDate, // 🎯 新增：事件发生的日期
  }) async {
    // 🎯 調試：輸出即將記錄的通知結果信息
    debugPrint('🎯 recordNotificationResult 開始');
    debugPrint('🎯 uid: $uid, eventId: $eventId, notifId: $notifId');
    debugPrint('🎯 result: ${result.value} (${result.name})');
    debugPrint('🎯 eventDate: $eventDate');
    
    // 🎯 修复：根据事件发生的日期获取正确的通知文档路径
    DocumentReference ref;
    if (eventDate != null) {
      debugPrint('🎯 使用事件日期獲取通知文檔路徑: eventDate=$eventDate');
      ref = await DataPathService.instance.getDateEventNotificationDoc(uid, eventId, notifId, eventDate);
    } else {
      debugPrint('🎯 使用當前日期獲取通知文檔路徑');
      ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);
    }
    
    debugPrint('🎯 通知文檔路徑: ${ref.path}');

    try {
      final updateData = <String, dynamic>{
        'result': result.value,
      };

      // 檢查文档是否存在
      final snap = await ref.get();
      if (snap.exists) {
        debugPrint('🎯 通知文檔已存在，準備更新');
        // 文檔存在，更新結果
        await ref.update(updateData);
        debugPrint('🎯 通知文檔更新成功: result=${result.value}');
        
        // 驗證更新結果
        final verifySnap = await ref.get();
        if (verifySnap.exists) {
          final verifyData = verifySnap.data() as Map<String, dynamic>;
          debugPrint('🎯 驗證更新結果: result=${verifyData['result']}, 預期=${result.value}');
          if (verifyData['result'] == result.value) {
            debugPrint('🎯 ✅ 驗證成功：通知結果已正確更新');
          } else {
            debugPrint('🎯 ❌ 驗證失敗：通知結果更新異常');
          }
        }
      } else {
        debugPrint('🎯 通知文檔不存在，準備創建新文檔');
        // 🎯 修復：如果文档不存在，创建一个新文档
        final createData = {
          'opened_time': null,
          'notification_scheduled_time': null, // 沒有排程記錄
          'result': result.value,
          'notif_to_click_sec': null,
          'created_at': FieldValue.serverTimestamp(),
        };
        
        await ref.set(createData);
        debugPrint('🎯 通知文檔創建成功: result=${result.value}');
        debugPrint('🎯 創建內容: $createData');
        
        // 驗證創建結果
        final verifySnap = await ref.get();
        if (verifySnap.exists) {
          final verifyData = verifySnap.data() as Map<String, dynamic>;
          debugPrint('🎯 驗證創建結果: result=${verifyData['result']}, 預期=${result.value}');
          if (verifyData['result'] == result.value) {
            debugPrint('🎯 ✅ 驗證成功：通知文檔已正確創建');
          } else {
            debugPrint('🎯 ❌ 驗證失敗：通知文檔創建異常');
          }
        }
      }
      
      debugPrint('🎯 recordNotificationResult 完成');
    } catch (e) {
      // 🎯 調試：輸出錯誤信息
      debugPrint('🎯 記錄通知結果失敗: notifId=$notifId, result=${result.value}, error=$e');
      debugPrint('🎯 嘗試路徑: ${ref.path}');
      debugPrint('🎯 錯誤詳情: $e');
      rethrow;
    }
  }

    /// 記錄聊天會話開始（實驗數據收集）
  static Future<void> recordChatStart({
    required String uid,
    required String eventId,
    required String chatId,
    required ChatEntryMethod entryMethod, // 🎯 新增：聊天進入方式
}) async {
    final now = DateTime.now();
    final ref = await _getChatRef(uid, eventId, chatId);

    // 🎯 調試：輸出即將創建的聊天會話數據
    debugPrint('recordChatStart - uid: $uid, eventId: $eventId, chatId: $chatId');
    debugPrint('recordChatStart - entryMethod: ${entryMethod.value}, start_time: $now');

    try {
      await ref.set({
        'start_time': Timestamp.fromDate(now),
        'entry_method': entryMethod.value, // 🎯 新增：記錄進入方式
        'end_time': null,
        'result': null,
        'commit_plan': null,
        'total_turns': 0,
        'total_tokens': 0,
        'avg_latency_ms': 0,
        'created_at': FieldValue.serverTimestamp(),
      });
      
      debugPrint('recordChatStart - 聊天會話創建成功');
    } catch (e) {
      debugPrint('recordChatStart - 創建失敗: $e');
      rethrow;
    }
  }

  /// 記錄聊天會話結束（實驗數據收集）
  static Future<void> recordChatEnd({
    required String uid,
    required String eventId,
    required String chatId,
    required int result, // 0-start, 1-snooze, 2-leave
    required String commitPlan,
  }) async {
    final now = DateTime.now();
    final ref = await _getChatRef(uid, eventId, chatId);

    // 🎯 調試：輸出即將更新的聊天結束數據
    debugPrint('recordChatEnd - uid: $uid, eventId: $eventId, chatId: $chatId');
    debugPrint('recordChatEnd - result: $result, commitPlan: $commitPlan, end_time: $now');

    try {
      // 使用 set 而不是 update，確保即使文檔不存在也能寫入
      await ref.set({
        'end_time': Timestamp.fromDate(now),
        'result': result,
        'commit_plan': commitPlan,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('recordChatEnd - 聊天結束記錄成功');
    } catch (e) {
      debugPrint('recordChatEnd - 記錄失敗: $e');
      rethrow;
    }
  }

  /// 更新聊天統計數據（實驗數據收集）
  static Future<void> updateChatStats({
    required String uid,
    required String eventId,
    required String chatId,
    required int totalTurns,
    required int totalTokens,
    required int avgLatencyMs,
  }) async {
    final ref = await _getChatRef(uid, eventId, chatId);

    // 🎯 調試：輸出即將更新的數據
    debugPrint('updateChatStats - uid: $uid, eventId: $eventId, chatId: $chatId');
    debugPrint('updateChatStats - totalTurns: $totalTurns, totalTokens: $totalTokens, avgLatencyMs: $avgLatencyMs');

    try {
      // 使用 set 而不是 update，確保即使文檔不存在也能寫入
      await ref.set({
        'total_turns': totalTurns,
        'total_tokens': totalTokens,
        'avg_latency_ms': avgLatencyMs,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('updateChatStats - 統計數據更新成功');
    } catch (e) {
      debugPrint('updateChatStats - 更新失敗: $e');
      rethrow;
    }
  }

  /// 添加單次對話延遲記錄（用於計算平均延遲）
  static Future<void> recordChatLatency({
    required String uid,
    required String eventId,
    required String chatId,
    required int latencyMs,
  }) async {
    final ref = await _getChatRef(uid, eventId, chatId);

    // 使用 arrayUnion 累積延遲數據，稍後用於計算平均值
    await ref.update({
      'latencies': FieldValue.arrayUnion([latencyMs]),
    });
  }

  /// 儲存聊天總結資料（實驗資料收集）
  static Future<void> saveChatSummary({
    required String uid,
    required String eventId,
    required String chatId,
    required String summary,
    required List<String> snoozeReasons,
    required List<String> coachMethods,
  }) async {
    final ref = await _getChatRef(uid, eventId, chatId);

    // 🎯 除錯：輸出即將儲存的總結資料
    debugPrint('saveChatSummary - uid: $uid, eventId: $eventId, chatId: $chatId');
    debugPrint('saveChatSummary - summary: $summary');
    debugPrint('saveChatSummary - snoozeReasons: $snoozeReasons');
    debugPrint('saveChatSummary - coachMethods: $coachMethods');

    try {
      // 使用 set 而不是 update，确保即使文档不存在也能写入
      await ref.set({
        'summary': summary,
        'snooze_reasons': snoozeReasons,
        'coach_methods': coachMethods,
        'summary_created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('saveChatSummary - 总结数据保存成功');
    } catch (e) {
      debugPrint('saveChatSummary - 保存失败: $e');
      rethrow;
    }
  }





  /// 🎯 私有方法：只在通知未發送時才記錄為 cancel 狀態
  /// 這用於處理任務開始時取消第二個通知，或任務完成時取消未發送的通知
  /// 不會覆蓋已經有用戶互動記錄的通知
  static Future<void> _recordNotificationCompleteIfNotExists(
    String uid, 
    String eventId, 
    String notifId, 
    DateTime? eventDate
  ) async {
    try {
      // 獲取通知文檔引用
      DocumentReference ref;
      if (eventDate != null) {
        ref = await DataPathService.instance.getDateEventNotificationDoc(uid, eventId, notifId, eventDate);
      } else {
        ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);
      }

      // 🎯 檢查通知文檔是否存在以及是否已經有用戶互動
      final snap = await ref.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        
        // 檢查是否已經有用戶互動（opened_time 不為 null 或 result 不是 dismiss）
        final hasUserInteraction = data['opened_time'] != null || 
                                  (data['result'] != null && data['result'] != NotificationResult.dismiss.value);
        
        if (hasUserInteraction) {
          if (kDebugMode) {
            print('🎯 通知 $notifId 已經有用戶互動，保持原狀態不覆蓋');
          }
          return; // 已經有用戶互動，不覆蓋狀態
        }
      }

      // 🎯 只有在通知未發送或沒有用戶互動時才記錄為 cancel 狀態
      await ref.set({
        'opened_time': null,
        'notification_scheduled_time': null,
        'result': NotificationResult.cancel.value, // 設為 cancel(4)
        'notif_to_click_sec': null,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        print('🎯 通知 $notifId 未發送或無用戶互動，已記錄為 cancel 狀態');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎯 記錄通知 cancel 狀態失敗: $notifId, error: $e');
      }
      // 不重新拋出錯誤，避免影響主要流程
    }
  }


}

/// 通知實驗數據模型
class NotificationData {
  final String id;                    // 通知ID
  final DateTime? openedTime;         // 用戶點擊時間
  final DateTime? notificationScheduledTime; // 通知排程時間
  final NotificationResult? result;   // 操作結果
  final int? notifToClickSec;        // 通知發送到點擊的秒數
  final DateTime? createdAt;         // 創建時間

  NotificationData({
    required this.id,
    this.openedTime,
    this.notificationScheduledTime,
    this.result,
    this.notifToClickSec,
    this.createdAt,
  });

  factory NotificationData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return NotificationData(
      id: doc.id,
      openedTime: (data['opened_time'] as Timestamp?)?.toDate(),
      notificationScheduledTime: (data['notification_scheduled_time'] as Timestamp?)?.toDate(),
      result: data['result'] != null 
          ? NotificationResult.fromValue(data['result']) 
          : null,
      notifToClickSec: data['notif_to_click_sec'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (openedTime != null) 'opened_time': Timestamp.fromDate(openedTime!),
      if (notificationScheduledTime != null) 'notification_scheduled_time': Timestamp.fromDate(notificationScheduledTime!),
      if (result != null) 'result': result!.value,
      if (notifToClickSec != null) 'notif_to_click_sec': notifToClickSec,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
    };
  }
} 
