import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'enums.dart';
import '../services/data_path_service.dart';

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
  
  // === 互動 ===
  final StartTrigger? startTrigger;     // enum:int 0-tap_notif 1-tap_card 2-chat 3-auto
  final String? chatId;                 // evt42_20250703T0130
  final List<String> notifIds;          // ["evt42-1st", "evt42-2nd"]
  
  // === 狀態 ===
  final TaskStatus? status;             // enum:int 0-NotStarted 1-InProgress 2-Completed 3-Overdue
  final int? startToOpenLatency;        // (actual - scheduled)/1000；預寫好省 ETL
  final bool isDone;

  // === 事件生命周期 ===
  final EventLifecycleStatus lifecycleStatus;  // 事件生命周期状态
  final DateTime? archivedAt;                    // 归档时间（被删除/移动的时间）
  final String? previousEventId;                 // 原事件ID（用于移动后ID相同的情况）
  final DateTime? movedFromStartTime;            // 移动前的开始时间
  final DateTime? movedFromEndTime;              // 移动前的结束时间

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
    this.description,
    this.actualStartTime,
    this.completedTime,
    this.startTrigger,
    this.chatId,
    List<String>? notifIds,
    this.status,
    this.startToOpenLatency,
    this.lifecycleStatus = EventLifecycleStatus.active,
    this.archivedAt,
    this.previousEventId,
    this.movedFromStartTime,
    this.movedFromEndTime,
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
      }) : notifIds = notifIds ?? [];

  factory EventModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data()! as Map<String, dynamic>;
    return EventModel(
      id: doc.id,
      title: d['title'],
      description: d['description'],
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
      lifecycleStatus: d['lifecycleStatus'] != null 
          ? EventLifecycleStatus.fromValue(d['lifecycleStatus']) 
          : EventLifecycleStatus.active,
      archivedAt: (d['archivedAt'] as Timestamp?)?.toDate(),
      previousEventId: d['previousEventId'],
      movedFromStartTime: (d['movedFromStartTime'] as Timestamp?)?.toDate(),
      movedFromEndTime: (d['movedFromEndTime'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      googleEventId: d['googleEventId'],
      googleCalendarId: d['googleCalendarId'],
              notifScheduledAt: (d['notifScheduledAt'] as Timestamp?)?.toDate(),
        expectedDurationMin: d['expectedDurationMin'],
        actualDurationMin: d['actualDurationMin'],
        pauseCount: d['pauseCount'],
        pauseAt: (d['pauseAt'] as Timestamp?)?.toDate(),
        resumeAt: (d['resumeAt'] as Timestamp?)?.toDate(),
      );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      if (description != null) 'description': description,
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
      'lifecycleStatus': lifecycleStatus.value,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      if (previousEventId != null) 'previousEventId': previousEventId,
      if (movedFromStartTime != null) 'movedFromStartTime': Timestamp.fromDate(movedFromStartTime!),
      if (movedFromEndTime != null) 'movedFromEndTime': Timestamp.fromDate(movedFromEndTime!),
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
      };
  }

  String get timeRange {
    final f = DateFormat('HH:mm');
    return '${f.format(scheduledStartTime.toLocal())} - ${f.format(scheduledEndTime.toLocal())}';
  }

  /// 是否为活跃事件（未被删除或移动）
  bool get isActive {
    return lifecycleStatus == EventLifecycleStatus.active;
  }

  /// 是否为已归档事件（被删除或移动）
  bool get isArchived {
    return lifecycleStatus != EventLifecycleStatus.active;
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
    StartTrigger? startTrigger,
    String? chatId,
    List<String>? notifIds,
    TaskStatus? status,
    int? startToOpenLatency,
    EventLifecycleStatus? lifecycleStatus,
    DateTime? archivedAt,
    String? previousEventId,
    DateTime? movedFromStartTime,
    DateTime? movedFromEndTime,
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
      startTrigger: startTrigger ?? this.startTrigger,
      chatId: chatId ?? this.chatId,
      notifIds: notifIds ?? this.notifIds,
      status: status ?? this.status,
      startToOpenLatency: startToOpenLatency ?? this.startToOpenLatency,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      archivedAt: archivedAt ?? this.archivedAt,
      previousEventId: previousEventId ?? this.previousEventId,
      movedFromStartTime: movedFromStartTime ?? this.movedFromStartTime,
      movedFromEndTime: movedFromEndTime ?? this.movedFromEndTime,
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
    );
  }
}


/// 實驗數據收集工具類
class ExperimentEventHelper {
  static final _firestore = FirebaseFirestore.instance;

  /// 获取用户事件文档引用（使用正确的数据路径）
  static Future<DocumentReference> _getEventRef(String uid, String eventId) async {
    return await DataPathService.instance.getUserEventDoc(uid, eventId);
  }

  /// 获取用户事件聊天文档引用（使用正确的数据路径）
  static Future<DocumentReference> _getChatRef(String uid, String eventId, String chatId) async {
    return await DataPathService.instance.getUserEventChatDoc(uid, eventId, chatId);
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
      if (chatId != null) 'chatId': chatId,
      if (actualDurationMin != null) 'actualDurationMin': actualDurationMin,
      if (expectedDurationMin != null) 'expectedDurationMin': expectedDurationMin,
    }, SetOptions(merge: true));
  }



  /// 記錄通知點擊（不開始任務，只記錄觸發源）
  static Future<void> recordNotificationTap({
    required String uid,
    required String eventId,
  }) async {
    final ref = await _getEventRef(uid, eventId);

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
    final ref = await _getEventRef(uid, eventId);

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
    final ref = await _getEventRef(uid, eventId);

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
    final ref = await _getEventRef(uid, eventId);

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
    DateTime? scheduledTime,
  }) async {
    try {
      final now = DateTime.now();
      
      // 使用 DataPathService 获取正确的通知文档路径
      final ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);

      await ref.set({
        'delivered_time': Timestamp.fromDate(now),
        'opened_time': null,
        'notification_scheduled_time': scheduledTime != null ? Timestamp.fromDate(scheduledTime) : null, // 新增字段
        'result': NotificationResult.dismiss.value,
        'snooze_minutes': null,
        'latency_sec': null,
        'notif_to_click_sec': null,
        'created_at': FieldValue.serverTimestamp(),
      });
      
      // 🎯 調試：確認記錄成功
      debugPrint('通知發送記錄創建成功: notifId=$notifId, scheduledTime=$scheduledTime');
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
  }) async {
    final now = DateTime.now();
    
    // 使用 DataPathService 获取正确的通知文档路径
    final ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);

    try {
      // 獲取已存在的數據來計算延遲
      final snap = await ref.get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final deliveredTime = (data['delivered_time'] as Timestamp?)?.toDate();
        final notifToClickSec = deliveredTime != null 
            ? now.difference(deliveredTime).inSeconds 
            : null;

        await ref.update({
          'opened_time': Timestamp.fromDate(now),
          'latency_sec': notifToClickSec, // 保持向後兼容
          'notif_to_click_sec': notifToClickSec, // 新字段
        });
      } else {
        // 🎯 修復：如果文档不存在，创建一个新文档
        await ref.set({
          'delivered_time': null, // 没有发送记录
          'opened_time': Timestamp.fromDate(now),
          'notification_scheduled_time': null, // 沒有排程記錄
          'result': NotificationResult.dismiss.value,
          'snooze_minutes': null,
          'latency_sec': null, // 无法计算延迟
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
    int? snoozeMinutes,
  }) async {
    // 使用 DataPathService 获取正确的通知文档路径
    final ref = await DataPathService.instance.getUserEventNotificationDoc(uid, eventId, notifId);

    try {
      final updateData = <String, dynamic>{
        'result': result.value,
      };

      if (result == NotificationResult.snooze && snoozeMinutes != null) {
        updateData['snooze_minutes'] = snoozeMinutes;
      }

      // 檢查文档是否存在
      final snap = await ref.get();
      if (snap.exists) {
        await ref.update(updateData);
      } else {
        // 🎯 修復：如果文档不存在，创建一个新文档
        await ref.set({
          'delivered_time': null,
          'opened_time': null,
          'notification_scheduled_time': null, // 沒有排程記錄
          'result': result.value,
          'snooze_minutes': snoozeMinutes,
          'latency_sec': null,
          'notif_to_click_sec': null,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // 🎯 調試：輸出錯誤信息
      debugPrint('記錄通知結果失敗: notifId=$notifId, result=${result.value}, error=$e');
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

  /// 手动归档事件（管理员功能）
  static Future<void> archiveEvent({
    required String uid,
    required String eventId,
    required EventLifecycleStatus lifecycleStatus,
    String? reason,
  }) async {
    final now = DateTime.now();
    final ref = await _getEventRef(uid, eventId);

    await ref.set({
      'lifecycleStatus': lifecycleStatus.value,
      'archivedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
      if (reason != null) 'archiveReason': reason,
    }, SetOptions(merge: true));

    debugPrint('archiveEvent - 事件已归档: eventId=$eventId, status=${lifecycleStatus.displayName}');
  }

  /// 恢复已归档的事件
  static Future<void> restoreEvent({
    required String uid,
    required String eventId,
  }) async {
    final now = DateTime.now();
    final ref = await _getEventRef(uid, eventId);

    await ref.set({
      'lifecycleStatus': EventLifecycleStatus.active.value,
      'archivedAt': null,
      'updatedAt': Timestamp.fromDate(now),
    }, SetOptions(merge: true));

    debugPrint('restoreEvent - 事件已恢复: eventId=$eventId');
  }

  /// 获取事件的生命周期历史（如果有关联的前一个事件）
  static Future<List<EventModel>> getEventHistory({
    required String uid,
    required String eventId,
  }) async {
    final history = <EventModel>[];
    var currentEventId = eventId;

    while (currentEventId.isNotEmpty) {
      final ref = await _getEventRef(uid, currentEventId);
      final doc = await ref.get();

      if (!doc.exists) break;

      final event = EventModel.fromDoc(doc);
      history.add(event);

      // 查找下一个关联的事件
      final previousEventId = event.previousEventId;
      if (previousEventId == null) break;

      currentEventId = previousEventId;
    }

    return history.reversed.toList(); // 按时间顺序返回
  }

  /// 查询已归档的事件
  static Future<List<EventModel>> getArchivedEvents({
    required String uid,
    EventLifecycleStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
    Query<Map<String, dynamic>> query = eventsCollection as Query<Map<String, dynamic>>;

    // 先查询特定状态，避免复合索引问题
    if (status != null) {
      query = query.where('lifecycleStatus', isEqualTo: status.value);
    }

    // 如果有时间范围，添加时间过滤
    if (startDate != null) {
      query = query.where('archivedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }

    if (endDate != null) {
      query = query.where('archivedAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }

    final snapshot = await query
        .limit(limit * 2) // 多获取一些数据以防过滤后不够
        .get();

    // 在内存中过滤出归档事件
    final archivedEvents = snapshot.docs
        .map(EventModel.fromDoc)
        .where((event) => event.isArchived)
        .where((event) {
          // 如果没有指定状态，只要是归档状态就行
          if (status == null) return true;
          return event.lifecycleStatus == status;
        })
        .toList();

    // 按归档时间排序并限制数量
    archivedEvents.sort((a, b) {
      if (a.archivedAt == null && b.archivedAt == null) return 0;
      if (a.archivedAt == null) return 1;
      if (b.archivedAt == null) return -1;
      return b.archivedAt!.compareTo(a.archivedAt!);
    });

    return archivedEvents.take(limit).toList();
  }

  /// 统计事件生命周期状态
  static Future<Map<EventLifecycleStatus, int>> getLifecycleStats({
    required String uid,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final stats = <EventLifecycleStatus, int>{
      EventLifecycleStatus.active: 0,
      EventLifecycleStatus.deleted: 0,
      EventLifecycleStatus.moved: 0,
    };

    final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
    Query<Map<String, dynamic>> query = eventsCollection as Query<Map<String, dynamic>>;

    if (startDate != null && endDate != null) {
      query = query
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }

    final snapshot = await query.get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final statusValue = data['lifecycleStatus'] as int?;
      // 现在默认为active，兼容旧数据中可能为null的情况
      final status = statusValue != null 
          ? EventLifecycleStatus.fromValue(statusValue)
          : EventLifecycleStatus.active;
      
      stats[status] = (stats[status] ?? 0) + 1;
    }

    return stats;
  }
}

/// 通知實驗數據模型
class NotificationData {
  final String id;                    // 通知ID
  final DateTime? deliveredTime;      // 發送成功時間
  final DateTime? openedTime;         // 用戶點擊時間
  final DateTime? notificationScheduledTime; // 通知排程時間
  final NotificationResult? result;   // 操作結果
  final int? snoozeMinutes;          // 延後分鐘數
  final int? latencySec;             // 延遲秒數（保留向後兼容）
  final int? notifToClickSec;        // 通知發送到點擊的秒數
  final DateTime? createdAt;         // 創建時間

  NotificationData({
    required this.id,
    this.deliveredTime,
    this.openedTime,
    this.notificationScheduledTime,
    this.result,
    this.snoozeMinutes,
    this.latencySec,
    this.notifToClickSec,
    this.createdAt,
  });

  factory NotificationData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return NotificationData(
      id: doc.id,
      deliveredTime: (data['delivered_time'] as Timestamp?)?.toDate(),
      openedTime: (data['opened_time'] as Timestamp?)?.toDate(),
      notificationScheduledTime: (data['notification_scheduled_time'] as Timestamp?)?.toDate(),
      result: data['result'] != null 
          ? NotificationResult.fromValue(data['result']) 
          : null,
      snoozeMinutes: data['snooze_minutes'],
      latencySec: data['latency_sec'],
      notifToClickSec: data['notif_to_click_sec'],
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      if (deliveredTime != null) 'delivered_time': Timestamp.fromDate(deliveredTime!),
      if (openedTime != null) 'opened_time': Timestamp.fromDate(openedTime!),
      if (notificationScheduledTime != null) 'notification_scheduled_time': Timestamp.fromDate(notificationScheduledTime!),
      if (result != null) 'result': result!.value,
      if (snoozeMinutes != null) 'snooze_minutes': snoozeMinutes,
      if (latencySec != null) 'latency_sec': latencySec,
      if (notifToClickSec != null) 'notif_to_click_sec': notifToClickSec,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
    };
  }
} 
