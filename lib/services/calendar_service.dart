import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:momentum/services/auth_service.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Light wrapper that adds Google OAuth headers to each request.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class CalendarService extends ChangeNotifier {
  CalendarService._();
  static final instance = CalendarService._();

  cal.CalendarApi? _api;
  DateTime? _lastSyncAt;
  bool _isSyncing = false;
  
  // Getters for UI state
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  
  void _setSyncingState(bool syncing) {
    if (_isSyncing != syncing) {
      _isSyncing = syncing;
      if (kDebugMode) {
        print('CalendarService: 同步狀態變更為 $_isSyncing');
      }
      notifyListeners();
    }
  }
  
  /// 重置同步狀態（用於調試）
  void resetSyncState() {
    _setSyncingState(false);
  }

  /// Must be called **after** Google Sign-in succeeds.
  Future<void> init(GoogleSignInAccount account) async {
    try {
      final authHeaders = await account.authHeaders;
      final client = _GoogleAuthClient(authHeaders);
      _api = cal.CalendarApi(client);
      
      // 測試 API 是否正常工作
      await _api!.calendarList.list();
      
      // 載入上次同步時間
      await _loadLastSyncAt();
      
      if (kDebugMode) {
        print('CalendarService 初始化成功');
      }
    } catch (e) {
      _api = null; // 重置 API 實例
      if (kDebugMode) {
        print('CalendarService 初始化失敗: $e');
      }
      rethrow;
    }
  }

  /// 從SharedPreferences載入lastSyncAt
  Future<void> _loadLastSyncAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncTimestamp = prefs.getInt('last_sync_at');
      if (lastSyncTimestamp != null) {
        _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp);
      }
    } catch (e) {
      // 如果載入失敗，使用預設值
      _lastSyncAt = null;
    }
  }

  /// 儲存lastSyncAt到SharedPreferences
  Future<void> _saveLastSyncAt(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_at', timestamp.millisecondsSinceEpoch);
      _lastSyncAt = timestamp;
    } catch (e) {
      // 如果儲存失敗，至少更新記憶體中的值
      _lastSyncAt = timestamp;
    }
  }

  Future<void> _ensureReady() async {
    if (kDebugMode) {
      print('_ensureReady: 開始檢查 API 狀態');
    }
    
    if (_api != null) {
      // 测试 API 是否仍然有效
      try {
        if (kDebugMode) {
          print('_ensureReady: 測試現有 API 實例');
        }
        await _api!.calendarList.list();
        if (kDebugMode) {
          print('_ensureReady: API 實例有效，直接返回');
        }
        return; // API 仍然有效
      } catch (e) {
        if (kDebugMode) {
          print('_ensureReady: Calendar API 測試失敗，需要重新初始化: $e');
        }
        // API 無效，重置並重新初始化
        _api = null;
      }
    }
    
    if (kDebugMode) {
      print('_ensureReady: 開始重新初始化 API');
    }
    
    final acct = AuthService.instance.googleAccount;
    if (acct != null) {
      try {
        if (kDebugMode) {
          print('_ensureReady: 使用現有帳號初始化: ${acct.email}');
        }
        await init(acct);
        if (kDebugMode) {
          print('_ensureReady: 使用現有帳號初始化成功');
        }
      } catch (e) {
        if (kDebugMode) {
          print('_ensureReady: 使用現有帳號初始化失敗: $e');
        }
        // 如果初始化失败，尝试重新登录
        try {
          if (kDebugMode) {
            print('_ensureReady: 嘗試重新登入');
          }
          await AuthService.instance.signInSilently();
          final newAcct = AuthService.instance.googleAccount;
          if (newAcct != null) {
            if (kDebugMode) {
              print('_ensureReady: 使用新帳號初始化: ${newAcct.email}');
            }
            await init(newAcct);
            if (kDebugMode) {
              print('_ensureReady: 使用新帳號初始化成功');
            }
          } else {
            throw StateError('無法獲取有效的 Google 帳號');
          }
        } catch (signInError) {
          if (kDebugMode) {
            print('_ensureReady: 重新登入失敗: $signInError');
          }
          throw StateError('CalendarService 初始化失敗: $signInError');
        }
      }
    } else {
      if (kDebugMode) {
        print('_ensureReady: 沒有可用的 Google 帳號');
      }
      throw StateError('CalendarService 未初始化');
    }
  }

  /// 強制完整同步未來一週事件（手動觸發）
  /// 注意：同步一週事件但UI只顯示當天
  Future<void> forceSyncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('手動觸發完整同步（未來一週事件）');
    }
    
    try {
      await syncToday(uid);
    } catch (e) {
      // 確保在錯誤時也重置同步狀態
      _setSyncingState(false);
      rethrow;
    }
  }

  /// App Resume 同步（同步未來一週事件）
  /// 注意：同步一週事件但UI只顯示當天
  Future<void> resumeSync(String uid) async {
    if (kDebugMode) {
      print('App Resume: 開始同步（未來一週事件）');
    }
    
    try {
      // 直接使用 syncToday，現在同步未來一週事件
      await syncToday(uid);
    } catch (e) {
      // 確保在錯誤時也重置同步狀態
      _setSyncingState(false);
      if (kDebugMode) {
        print('Resume sync 失敗: $e');
      }
      // 不重新拋出錯誤，避免影響 UI
    }
  }

  /// Syncs next week's events from *primary* calendar into Firestore `/events`.
  Future<void> syncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('syncToday: 開始同步未來一週事件，UID: $uid');
    }
    
    _setSyncingState(true);
    try {
      await _ensureReady();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 7)); // 改為7天

      if (kDebugMode) {
        print('syncToday: 查詢 Google Calendar 事件，時間範圍: $start 到 $end（未來7天）');
      }

      // 查找名為 "experiment" 的日历
      String targetCalendarId = 'primary'; // 默认使用主日历
      
      try {
        final calendarList = await _api!.calendarList.list();
        for (final calendar in calendarList.items ?? <cal.CalendarListEntry>[]) {
          if (calendar.summary?.toLowerCase() == 'experiment' || 
              calendar.summary?.toLowerCase() == 'experiments') {
            targetCalendarId = calendar.id!;
            if (kDebugMode) {
              print('syncToday: 找到 experiment 日历，ID: $targetCalendarId');
            }
            break;
          }
        }
        
        if (targetCalendarId == 'primary') {
          if (kDebugMode) {
            print('syncToday: 未找到 experiment 日历，使用主日历');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('syncToday: 获取日历列表失败: $e，使用主日历');
        }
      }

      final apiEvents = await _api!.events.list(
        targetCalendarId,
        timeMin: start,
        timeMax: end,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (kDebugMode) {
        print('syncToday: 從日历 $targetCalendarId 獲取到 ${apiEvents!.items?.length ?? 0} 個事件');
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events');

      // 创建事件映射：googleEventId -> Google Calendar事件
      final apiEventMap = <String, cal.Event>{};
      final idsToday = <String>{};

      for (final e in apiEvents!.items ?? <cal.Event>[]) {
        if (e.id != null && e.start?.dateTime != null && e.end?.dateTime != null) {
          apiEventMap[e.id!] = e;
          idsToday.add(e.id!);
        }
      }

      // 1) 获取本地事件进行比较
      final localSnap = await col
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .get();

      final batch = FirebaseFirestore.instance.batch();
      final archivedEvents = <String>[];
      final newEventIds = <String>[];

      // 2) 处理每个本地事件
      for (final localDoc in localSnap.docs) {
        final localData = localDoc.data();
        final localEventId = localDoc.id;
        final googleEventId = localData['googleEventId'] as String?;
        final localCalendarId = localData['googleCalendarId'] as String?;
        final currentLifecycleStatus = localData['lifecycleStatus'] as int?;
        
        // 跳过已经被归档的事件
        if (currentLifecycleStatus != null && currentLifecycleStatus != EventLifecycleStatus.active.value) {
          continue;
        }

        if (googleEventId != null && apiEventMap.containsKey(googleEventId)) {
          // 事件在Google Calendar中存在，检查是否有变化
          final apiEvent = apiEventMap[googleEventId]!;
          final apiStart = apiEvent.start!.dateTime!;
          final apiEnd = apiEvent.end!.dateTime!;
          final localStart = (localData['scheduledStartTime'] as Timestamp).toDate();
          final localEnd = (localData['scheduledEndTime'] as Timestamp).toDate();
          
          // 检查时间是否发生变化（移动）
          if (_hasTimeChanged(localStart, localEnd, apiStart, apiEnd)) {
            if (kDebugMode) {
              print('syncToday: 检测到事件移动: ${localData['title']} (ID: $localEventId)');
              print('  从 ${localStart.toIso8601String()} - ${localEnd.toIso8601String()}');
              print('  到 ${apiStart.toIso8601String()} - ${apiEnd.toIso8601String()}');
            }
            
            await _handleEventMove(uid, col, localDoc, apiEvent, targetCalendarId, now, batch);
            archivedEvents.add(localEventId);
          } else {
            // 事件没有重大变化，更新其他可能的字段
            await _updateExistingEvent(col, localDoc, apiEvent, targetCalendarId, now);
          }
        } else {
          // 事件在Google Calendar中不存在，检查是否移动到其他日历或被删除
          final lifecycleStatus = await _determineEventFate(googleEventId, localCalendarId, targetCalendarId);
          
          if (kDebugMode) {
            print('syncToday: 事件不存在于当前日历: ${localData['title']} (ID: $localEventId), 状态: ${lifecycleStatus.displayName}');
          }
          
          await _archiveEvent(col, localDoc, lifecycleStatus, now, batch);
          archivedEvents.add(localEventId);
        }
      }

      // 3) 添加新事件
      for (final apiEvent in apiEvents!.items ?? <cal.Event>[]) {
        final s = apiEvent.start?.dateTime, t = apiEvent.end?.dateTime;
        if (s == null || t == null || apiEvent.id == null) continue;

        // 检查是否为新事件（在本地不存在或已被归档）
        final existingDocsList = localSnap.docs.where((doc) => 
          doc.id == apiEvent.id && 
          (doc.data()['lifecycleStatus'] == null || 
           doc.data()['lifecycleStatus'] == EventLifecycleStatus.active.value)
        ).toList();
        final existingDoc = existingDocsList.isNotEmpty ? existingDocsList.first : null;

        if (existingDoc == null) {
          // 创建新事件
          final ref = col.doc(apiEvent.id);
          final data = <String, dynamic>{
            'title': apiEvent.summary ?? 'No title',
            if (apiEvent.description != null) 'description': apiEvent.description,
            'scheduledStartTime': Timestamp.fromDate(s.toUtc()),
            'scheduledEndTime': Timestamp.fromDate(t.toUtc()),
            'googleEventId': apiEvent.id,
            'googleCalendarId': targetCalendarId,
            'lifecycleStatus': EventLifecycleStatus.active.value,
            'updatedAt': Timestamp.fromDate(apiEvent.updated?.toUtc() ?? now.toUtc()),
            'isDone': false,
            'createdAt': Timestamp.fromDate(now.toUtc()),
          };

          batch.set(ref, data);
          newEventIds.add(apiEvent.id!);
          
          if (kDebugMode) {
            print('syncToday: 创建新事件: ${apiEvent.summary} (ID: ${apiEvent.id})');
          }
        }
      }

      // 4) 提交批量操作
      if (archivedEvents.isNotEmpty || newEventIds.isNotEmpty) {
        await batch.commit();
        if (kDebugMode) {
          print('syncToday: 已处理 ${archivedEvents.length} 个归档事件，创建 ${newEventIds.length} 个新事件');
        }
      }

      // 5) 重新读取活跃事件用于状态更新和通知
      final activeSnap = await col
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      // 在内存中过滤活跃事件，避免需要复合索引
      final activeEvents = activeSnap.docs
          .map(EventModel.fromDoc)
          .where((event) => event.isActive)
          .toList();
      
      // 6) 更新任务状态
      if (activeEvents.isNotEmpty) {
        await _updateEventStatuses(uid, activeEvents, now);
        if (kDebugMode) {
          print('syncToday: 更新了 ${activeEvents.length} 个活跃事件的状态（未来7天）');
        }
      }

      // 7) 同步通知排程
      if (activeEvents.isNotEmpty) {
        await NotificationScheduler().sync(activeEvents);
        if (kDebugMode) {
          print('syncToday: 同步了 ${activeEvents.length} 个活跃事件的通知排程（未来7天）');
        }
      }
      
      // 更新并储存lastSyncAt
      await _saveLastSyncAt(now);
      
      if (kDebugMode) {
        print('syncToday: 同步完成');
      }
    } catch (e) {
      if (kDebugMode) {
        print('syncToday: 同步失敗: $e');
      }
      rethrow;
    } finally {
      _setSyncingState(false);
    }
  }

  /// 检查事件时间是否发生变化
  bool _hasTimeChanged(DateTime localStart, DateTime localEnd, DateTime apiStart, DateTime apiEnd) {
    // 允许几秒钟的误差（处理时区和精度问题）
    const tolerance = Duration(seconds: 30);
    
    return (localStart.difference(apiStart).abs() > tolerance) ||
           (localEnd.difference(apiEnd).abs() > tolerance);
  }

  /// 处理事件移动
  Future<void> _handleEventMove(
    String uid,
    CollectionReference col,
    QueryDocumentSnapshot localDoc,
    cal.Event apiEvent,
    String targetCalendarId,
    DateTime now,
    WriteBatch batch,
  ) async {
    final localData = localDoc.data() as Map<String, dynamic>;
    final originalStart = (localData['scheduledStartTime'] as Timestamp).toDate();
    final originalEnd = (localData['scheduledEndTime'] as Timestamp).toDate();
    final originalEventId = localDoc.id;
    
    // 取消原事件的通知
    final notifIds = (localData['notifIds'] as List<dynamic>?)?.cast<String>() ?? [];
    if (notifIds.isNotEmpty) {
      await NotificationScheduler().cancelEventNotification(originalEventId, notifIds);
    }
    
    // 生成移动记录的事件ID（原ID + _moved + 时间戳）
    final movedEventId = '${originalEventId}_moved_${now.millisecondsSinceEpoch}';
    
    // 1) 将原事件文档重命名为移动记录（保存历史）
    final movedRef = col.doc(movedEventId);
    final movedData = Map<String, dynamic>.from(localData);
    movedData.addAll({
      'lifecycleStatus': EventLifecycleStatus.moved.value,
      'archivedAt': Timestamp.fromDate(now),
      'movedFromStartTime': Timestamp.fromDate(originalStart),
      'movedFromEndTime': Timestamp.fromDate(originalEnd),
      'updatedAt': Timestamp.fromDate(now),
    });
    
    batch.set(movedRef, movedData);
    
    // 2) 删除原文档
    batch.delete(localDoc.reference);
    
    // 3) 重新创建原ID的文档（使用Google Calendar的新数据）
    final originalRef = col.doc(originalEventId);
    final newData = <String, dynamic>{
      'title': apiEvent.summary ?? localData['title'],
      if (apiEvent.description != null) 'description': apiEvent.description,
      'scheduledStartTime': Timestamp.fromDate(apiEvent.start!.dateTime!.toUtc()),
      'scheduledEndTime': Timestamp.fromDate(apiEvent.end!.dateTime!.toUtc()),
      'googleEventId': apiEvent.id,
      'googleCalendarId': targetCalendarId,
      'lifecycleStatus': EventLifecycleStatus.active.value,
      'previousEventId': movedEventId, // 关联到移动记录
      'updatedAt': Timestamp.fromDate(apiEvent.updated?.toUtc() ?? now.toUtc()),
      'createdAt': Timestamp.fromDate(now),
      'isDone': false, // 移动后重置完成状态
    };
    
    // 如果原事件有重要的实验数据，可以选择性保留
    if (localData['actualStartTime'] != null) {
      newData['actualStartTime'] = localData['actualStartTime'];
    }
    if (localData['startTrigger'] != null) {
      newData['startTrigger'] = localData['startTrigger'];
    }
    if (localData['chatId'] != null) {
      newData['chatId'] = localData['chatId'];
    }
    
    batch.set(originalRef, newData);
    
    if (kDebugMode) {
      print('_handleEventMove: 原事件移至: $movedEventId, 新事件创建: $originalEventId');
    }
  }

  /// 更新现有事件
  Future<void> _updateExistingEvent(
    CollectionReference col,
    QueryDocumentSnapshot localDoc,
    cal.Event apiEvent,
    String targetCalendarId,
    DateTime now,
  ) async {
    final updateData = <String, dynamic>{
      'title': apiEvent.summary ?? 'No title',
      if (apiEvent.description != null) 'description': apiEvent.description,
      'googleCalendarId': targetCalendarId,
      'lifecycleStatus': EventLifecycleStatus.active.value,
      'updatedAt': Timestamp.fromDate(apiEvent.updated?.toUtc() ?? now.toUtc()),
    };

    await localDoc.reference.set(updateData, SetOptions(merge: true));
  }

  /// 确定事件的命运（删除或迁移）
  Future<EventLifecycleStatus> _determineEventFate(
    String? googleEventId,
    String? originalCalendarId,
    String targetCalendarId,
  ) async {
    // 简化处理：如果不在目标日历中，统一视为删除
    return EventLifecycleStatus.deleted;
  }

  /// 归档事件
  Future<void> _archiveEvent(
    CollectionReference col,
    QueryDocumentSnapshot localDoc,
    EventLifecycleStatus lifecycleStatus,
    DateTime now,
    WriteBatch batch,
  ) async {
    final localData = localDoc.data() as Map<String, dynamic>;
    
    // 取消事件的通知
    final notifIds = (localData['notifIds'] as List<dynamic>?)?.cast<String>() ?? [];
    if (notifIds.isNotEmpty) {
      await NotificationScheduler().cancelEventNotification(localDoc.id, notifIds);
    }
    
    // 标记为归档
    batch.update(localDoc.reference, {
      'lifecycleStatus': lifecycleStatus.value,
      'archivedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    
    if (kDebugMode) {
      print('_archiveEvent: 归档事件: ${localData['title']} (ID: ${localDoc.id}), 状态: ${lifecycleStatus.displayName}');
    }
  }

  Future<void> toggleEventDone(String uid, EventModel event,
      {bool pushToCalendar = false}) async {
    final newDone = !event.isDone;

    // 🎯 實驗數據收集：記錄任務狀態變更（包含相關字段的設置）
    if (newDone) {
      // recordEventCompletion 已設置 isDone, completedTime, updatedAt
      await ExperimentEventHelper.recordEventCompletion(
        uid: uid,
        eventId: event.id,
        chatId: event.chatId,
      );
    } else {
      // 如果是取消完成，更新狀態為進行中或未開始
      final newStatus = event.actualStartTime != null 
          ? TaskStatus.inProgress 
          : TaskStatus.notStarted;
      // updateEventStatus 已設置 updatedAt  
      await ExperimentEventHelper.updateEventStatus(
        uid: uid,
        eventId: event.id,
        status: newStatus,
      );
      
      // 需要額外清空 completedTime
      final doc = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .doc(event.id);

      await doc.set({
        'isDone': false,
        'completedTime': null,
      }, SetOptions(merge: true));
    }
  }

  Future<void> startEvent(String uid, EventModel e) async {
    // 🎯 實驗數據收集：記錄卡片點擊觸發（包含actualStartTime, updatedAt, isDone等）
    await ExperimentEventHelper.recordEventStart(
      uid: uid,
      eventId: e.id,
      startTrigger: StartTrigger.tapCard,
    );

    // 📅 排程任務完成提醒通知
    await _scheduleCompletionNotification(e);
  }

  /// 排程任務完成提醒通知
  Future<void> _scheduleCompletionNotification(EventModel event) async {
    try {
      // 計算動態結束時間（實際開始時間 + 任務時長）
      final now = DateTime.now();
      final taskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
      final targetEndTime = now.add(taskDuration);
      
      // 計算延遲秒數
      final delaySeconds = targetEndTime.difference(now).inSeconds;
      
      // 只有當延遲時間為正數時才排程通知
      if (delaySeconds > 0) {
        // 使用固定的算法生成通知ID
        final notificationId = 'task_completion_${event.id}'.hashCode.abs();
        
        final success = await NotificationService.instance.scheduleEventNotification(
          notificationId: notificationId,
          title: event.title,
          eventStartTime: targetEndTime,
          offsetMinutes: 0, // 無偏移，準確在結束時間觸發
          payload: 'task_completion_${event.id}',
          isSecondNotification: false,
          customTitle: '⏰ 任務時間到了！',
          customBody: '「${event.title}」的預計時間已結束，記得回來按完成哦！',
        );
        
        if (success && kDebugMode) {
          print('任務完成提醒通知已排程: ${event.title}, notificationId=$notificationId, 將於 $targetEndTime 觸發');
        }
      } else if (kDebugMode) {
        print('任務時長為負數或零，不排程完成提醒: ${event.title}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('排程任務完成提醒通知失敗: $e');
      }
    }
  }

  Future<void> stopEvent(String uid, EventModel e) async {
    // 🎯 計算新狀態：根據當前時間決定是未開始還是逾期
    final newStatus = DateTime.now().isAfter(e.scheduledStartTime) 
        ? TaskStatus.overdue 
        : TaskStatus.notStarted;
    
    // 一次性設置所有需要的字段，避免時序問題
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('events')
        .doc(e.id);

    await ref.set({
      'actualStartTime': null,           // 清空開始時間
      'status': newStatus.value,         // 設置新狀態  
      'updatedAt': Timestamp.fromDate(DateTime.now()), // 更新時間
    }, SetOptions(merge: true));

    // 取消任務完成提醒通知
    await _cancelCompletionNotification(e.id);
  }

  Future<void> completeEvent(String uid, EventModel e) async {
    // 🎯 實驗數據收集：記錄任務完成（包含isDone, completedTime, updatedAt）
    await ExperimentEventHelper.recordEventCompletion(
      uid: uid,
      eventId: e.id,
      chatId: e.chatId,
    );

    // 取消第二個通知（因為任務已經開始）
    if (e.notifIds.contains('${e.id}-2nd')) {
      await NotificationScheduler().cancelSecondNotification(e.id);
    }

    // 取消任務完成提醒通知
    await _cancelCompletionNotification(e.id);
  }

  /// 更新事件狀態（用於同步時檢查overdue/notStarted狀態）
  Future<void> _updateEventStatuses(String uid, List<EventModel> events, DateTime now) async {
    final batch = FirebaseFirestore.instance.batch();
    bool hasBatchUpdates = false;

    for (final event in events) {
      // 跳過已完成的任務
      if (event.isDone) continue;

      TaskStatus newStatus;
      
      if (event.actualStartTime != null) {
        // 任務已開始但未完成 → 保持進行中
        newStatus = TaskStatus.inProgress;
      } else {
        // 任務未開始，根據時間判斷狀態
        if (now.isAfter(event.scheduledStartTime)) {
          // 已過預定開始時間 → 逾期
          newStatus = TaskStatus.overdue;
        } else {
          // 尚未到預定開始時間 → 未開始
          newStatus = TaskStatus.notStarted;
        }
      }

      // 檢查是否需要更新狀態
      if (event.status != newStatus) {
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('events')
            .doc(event.id);

        batch.update(ref, {
          'status': newStatus.value,
          'updatedAt': Timestamp.fromDate(now),
        });
        
        hasBatchUpdates = true;
        
        if (kDebugMode) {
          print('_updateEventStatuses: 更新事件狀態: ${event.title} -> ${newStatus.name}');
        }
      }
    }

    // 批量提交更新
    if (hasBatchUpdates) {
      await batch.commit();
      if (kDebugMode) {
        print('_updateEventStatuses: 批量狀態更新完成');
      }
    }
  }

  /// 取消任務完成提醒通知
  Future<void> _cancelCompletionNotification(String eventId) async {
    try {
      // 使用固定的算法生成通知ID（類似NotificationScheduler的做法）
      final notificationId = 'task_completion_$eventId'.hashCode.abs();
      await NotificationService.instance.cancelNotification(notificationId);
      
      if (kDebugMode) {
        print('任務完成提醒通知已取消: eventId=$eventId, notificationId=$notificationId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('取消任務完成提醒通知失敗: $e');
      }
    }
  }
}
