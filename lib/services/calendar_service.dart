import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:momentum/services/auth_service.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data_path_service.dart';
import '../services/notification_service.dart';
import 'experiment_config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'day_number_service.dart';

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
  bool get isInitialized => _api != null;
  
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

  /// 获取日历列表
  Future<cal.CalendarList> getCalendarList() async {
    await _ensureReady();
    return await _api!.calendarList.list();
  }

  /// 获取事件列表
  Future<cal.Events> getEvents(String calendarId, {required DateTime start, required DateTime end}) async {
    await _ensureReady();
    return await _api!.events.list(
      calendarId,
      timeMin: start,
      timeMax: end,
      singleEvents: true,
      orderBy: 'startTime',
    );
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

  /// 強制完整同步當天事件（手動觸發）
  /// 注意：同步當天事件但UI只顯示當天
  Future<void> forceSyncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('手動觸發完整同步（當天事件）');
    }
    
    try {
      await syncToday(uid);
    } catch (e) {
      // 確保在錯誤時也重置同步狀態
      _setSyncingState(false);
      rethrow;
    }
  }

  /// App Resume 同步（同步當天事件）
  /// 注意：同步當天事件但UI只顯示當天
  Future<void> resumeSync(String uid) async {
    if (kDebugMode) {
      print('App Resume: 開始同步（當天事件）');
    }
    
    try {
      // 直接使用 syncToday，現在同步當天事件
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

  /// 同步「今天起未來 days 天」的事件進入 Firestore（w1/w2），並為未來事件排程通知
  Future<void> syncUpcomingDaysAndSchedule(String uid, {int days = 15}) async {
    try {
      await _ensureReady();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(Duration(days: days));

      // 目標日曆（優先找 experiment）
      String targetCalendarId = 'primary';
      try {
        final calendarList = await _api!.calendarList.list();
        for (final calendar in calendarList.items ?? <cal.CalendarListEntry>[]) {
          if (calendar.summary?.toLowerCase() == 'experiment' ||
              calendar.summary?.toLowerCase() == 'experiments') {
            targetCalendarId = calendar.id!;
            break;
          }
        }
      } catch (_) {}

      // 取得未來範圍事件
      final apiEvents = await _api!.events.list(
        targetCalendarId,
        timeMin: start,
        timeMax: end,
        singleEvents: true,
        orderBy: 'startTime',
      );

      // 以日期分組
      final eventsByDate = <DateTime, List<cal.Event>>{};
      for (final ev in apiEvents.items ?? <cal.Event>[]) {
        final s = ev.start?.dateTime, t = ev.end?.dateTime;
        if (ev.id == null || s == null || t == null) continue;
        final localDate = DateTime(s.year, s.month, s.day);
        eventsByDate.putIfAbsent(localDate, () => <cal.Event>[]).add(ev);
      }

      final batch = FirebaseFirestore.instance.batch();

      // 寫入/更新 Firestore（各日的 w1/w2）
      for (final entry in eventsByDate.entries) {
        final localDate = entry.key.toLocal();
        final col = await DataPathService.instance.getDateEventsCollection(uid, localDate);
        for (final ev in entry.value) {
          final s = ev.start!.dateTime!, t = ev.end!.dateTime!;
          final docRef = col.doc(ev.id);
          final dayNumber = await DayNumberService().calculateDayNumber(s.toLocal());
          final data = <String, dynamic>{
            'title': ev.summary ?? 'Untitled',
            if (ev.description != null) 'description': ev.description,
            'scheduledStartTime': Timestamp.fromDate(s.toUtc()),
            'scheduledEndTime': Timestamp.fromDate(t.toUtc()),
            'date': Timestamp.fromDate(s.toLocal()),
            'dayNumber': dayNumber,
            'googleEventId': ev.id,
            'googleCalendarId': targetCalendarId,

            'updatedAt': Timestamp.fromDate(ev.updated?.toUtc() ?? now.toUtc()),
            'isDone': false,
          };
          batch.set(docRef, data, SetOptions(merge: true));
        }
      }

      // 提交批次
      await batch.commit();

      // 排程今天起未來的事件（僅限尚未開始且未完成）
      for (int i = 0; i < days; i++) {
        final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
        final startOfDay = day.toUtc();
        final endOfDay = day.add(const Duration(days: 1)).toUtc();
        final col = await DataPathService.instance.getDateEventsCollection(uid, day);
        final snap = await col
            .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('scheduledStartTime', isLessThan: Timestamp.fromDate(endOfDay))
            .orderBy('scheduledStartTime')
            .get();
        final all = snap.docs.map(EventModel.fromDoc).toList();
        final futureEvents = all.where((e) => !e.isDone && e.scheduledStartTime.isAfter(now)).toList();
        if (futureEvents.isNotEmpty) {
          await NotificationScheduler().sync(futureEvents);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('syncUpcomingDaysAndSchedule 失敗: $e');
      }
    }
  }

  /// Syncs today's events from *primary* calendar into Firestore `/events`.
  Future<void> syncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('syncToday: 開始同步當天事件，UID: $uid');
    }
    
    _setSyncingState(true);
    try {
      await _ensureReady();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 1)); // 只處理當天

      if (kDebugMode) {
        print('syncToday: 查詢 Google Calendar 事件，時間範圍: $start 到 $end（當天）');
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

      // 使用 DataPathService 获取正确的 events 集合
      final col = await DataPathService.instance.getUserEventsCollection(uid);

      // 确保数据结构存在
      try {
        // 使用新的數據結構，不需要創建額外的配置文檔
        if (kDebugMode) {
          print('syncToday: 使用新的數據結構');
        }
      } catch (e) {
        if (kDebugMode) {
          print('syncToday: 檢查數據結構時出錯: $e');
        }
      }

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

      if (kDebugMode) {
        print('syncToday: 本地查询时间范围: $start 到 $end');
        print('syncToday: 找到 ${localSnap.docs.length} 个本地事件');
        for (final doc in localSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final localStart = (data['scheduledStartTime'] as Timestamp?)?.toDate();
          print('  本地事件: ${data['title']}, 时间: $localStart, ID: ${doc.id}');
        }
      }

      final batch = FirebaseFirestore.instance.batch();
      final archivedEvents = <String>[];
      final newEventIds = <String>[];

      // 2) 处理每个本地事件
      for (final localDoc in localSnap.docs) {
        final localData = localDoc.data() as Map<String, dynamic>?;
        final localEventId = localDoc.id;
        final googleEventId = localData?['googleEventId'] as String?;
        final localCalendarId = localData?['googleCalendarId'] as String?;



        if (googleEventId != null && apiEventMap.containsKey(googleEventId)) {
          // 事件在Google Calendar中存在，检查是否有变化
          final apiEvent = apiEventMap[googleEventId]!;
          final apiStart = apiEvent.start?.dateTime;
          final apiEnd = apiEvent.end?.dateTime;
          
          if (apiStart == null || apiEnd == null) continue;
          final localStart = (localData?['scheduledStartTime'] as Timestamp?)?.toDate();
          final localEnd = (localData?['scheduledEndTime'] as Timestamp?)?.toDate();
          
          if (localStart == null || localEnd == null) continue;
          
          // 事件存在，只更新非时间相关的字段（标题、描述等）
          await _updateExistingEvent(col, localDoc, apiEvent, targetCalendarId, now);
        } else {
          // 事件在Google Calendar中不存在，检查是否移动到其他日历或被删除
                    if (kDebugMode) {
            print('syncToday: 事件不存在于当前日历: ${localData?['title']} (ID: $localEventId)');
          }

          await _archiveEvent(col, localDoc, now, batch);
          archivedEvents.add(localEventId);
        }
      }

      // 3) 添加新事件
      if (kDebugMode) {
        print('syncToday: 开始检查新事件...');
        print('syncToday: Google Calendar API 返回的事件:');
        for (final apiEvent in apiEvents!.items ?? <cal.Event>[]) {
          final s = apiEvent.start?.dateTime;
          print('  API事件: ${apiEvent.summary ?? 'No title'}, 时间: $s, ID: ${apiEvent.id}');
        }
      }
      
      for (final apiEvent in apiEvents!.items ?? <cal.Event>[]) {
        final s = apiEvent.start?.dateTime, t = apiEvent.end?.dateTime;
        if (s == null || t == null || apiEvent.id == null) continue;

        // 检查是否为新事件（在本地不存在或已被归档）
        final existingDocsList = localSnap.docs.where((doc) {
          // 1) 首先检查ID是否匹配
          if (doc.id != apiEvent.id) return false;
          
          // 2) 然后检查事件是否为活跃状态
          final data = doc.data() as Map<String, dynamic>?;
                    // 所有事件都是活躍的（不再使用 lifecycleStatus）
          return true;
        }).toList();
        final existingDoc = existingDocsList.isNotEmpty ? existingDocsList.first : null;

        if (existingDoc == null) {
          // 根据事件日期获取正确的组别和集合
          final eventDate = s.toLocal();
          // 依日期的 dayNumber 決定 w1/w2
          final correctEventsCollection = await DataPathService.instance.getDateEventsCollection(uid, eventDate);
          
          // 计算dayNumber
          final dayNumber = await DayNumberService().calculateDayNumber(eventDate);
          
          // 创建新事件到正确的週別集合
          final ref = correctEventsCollection.doc(apiEvent.id);
          final data = <String, dynamic>{
            'title': apiEvent.summary ?? 'No title',
            if (apiEvent.description != null) 'description': apiEvent.description,
            'scheduledStartTime': Timestamp.fromDate(s.toUtc()),
            'scheduledEndTime': Timestamp.fromDate(t.toUtc()),
            'date': Timestamp.fromDate(eventDate), // 添加日期字段
            'dayNumber': dayNumber, // 添加dayNumber字段
            'googleEventId': apiEvent.id,
            'googleCalendarId': targetCalendarId,

            'updatedAt': Timestamp.fromDate(apiEvent.updated?.toUtc() ?? now.toUtc()),
            'isDone': false,
            'createdAt': Timestamp.fromDate(now.toUtc()),
          };

          batch.set(ref, data);
          newEventIds.add(apiEvent.id!);
          
          if (kDebugMode) {
            final weekFolder = (await DataPathService.instance.getDateEventsCollection(uid, eventDate)).id;
            print('syncToday: 创建新事件: ${apiEvent.summary ?? 'No title'} (ID: ${apiEvent.id}) 到資料夾: $weekFolder');
            print('  事件时间: ${eventDate} (本地) / ${s.toUtc()} (UTC)');
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

          .toList();
      
      // 6) 更新任务状态
      if (activeEvents.isNotEmpty) {
        await _updateEventStatuses(uid, activeEvents, now);
        if (kDebugMode) {
          print('syncToday: 更新了 ${activeEvents.length} 个活跃事件的状态（当天）');
        }
      }

      // 7) 通知排程已在用户初始化时完成，此处不再重复排定
      
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

      'updatedAt': Timestamp.fromDate(apiEvent.updated?.toUtc() ?? now.toUtc()),
    };

    // 盡量補齊 date 與 dayNumber（若缺少）
    final apiStart = apiEvent.start?.dateTime;
    if (apiStart != null) {
      final localDate = apiStart.toLocal();
      updateData['date'] = Timestamp.fromDate(localDate);
      try {
        final dayNumber = await DayNumberService().calculateDayNumber(localDate);
        updateData['dayNumber'] = dayNumber;
      } catch (_) {}
    }

    await localDoc.reference.set(updateData, SetOptions(merge: true));
  }



  /// 归档事件
  Future<void> _archiveEvent(
    CollectionReference col,
    QueryDocumentSnapshot localDoc,
    DateTime now,
    WriteBatch batch,
  ) async {
    final localData = localDoc.data() as Map<String, dynamic>;
    
    // 通知管理已在用户初始化时完成，此处不再处理
    
    // 标记为归档
    batch.update(localDoc.reference, {
      'archivedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    
    if (kDebugMode) {
      print('_archiveEvent: 归档事件: ${localData['title']} (ID: ${localDoc.id})');
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
      final doc = await DataPathService.instance.getEventDocAuto(uid, event.id);

      await doc.set({
        'isDone': false,
        'completedTime': null,
      }, SetOptions(merge: true));
    }
  }

  Future<void> startEvent(String uid, EventModel e, {String? notifId, StartTrigger? startTrigger}) async {
    // 🎯 實驗數據收集：記錄任務開始觸發（包含actualStartTime, updatedAt, isDone等）
    await ExperimentEventHelper.recordEventStart(
      uid: uid,
      eventId: e.id,
      startTrigger: startTrigger ?? StartTrigger.tapCard, // 允許傳入觸發方式，預設為點擊卡片
    );

    // 🎯 移除：通知結果記錄邏輯已移至 TaskStartDialog 中處理
    // 避免重複記錄，確保數據一致性
    if (kDebugMode && notifId != null) {
      print('🎯 startEvent: 通知結果記錄已移至 TaskStartDialog 處理');
      print('🎯 notifId: $notifId, eventId: ${e.id}');
    }
  }

  /// 從聊天開始任務（用於聊天頁面的開始任務按鈕）
  Future<void> startEventFromChat(String uid, EventModel e) async {
    // 🎯 實驗數據收集：記錄聊天觸發（包含actualStartTime, updatedAt, isDone等）
    await ExperimentEventHelper.recordEventStart(
      uid: uid,
      eventId: e.id,
      startTrigger: StartTrigger.chat,
    );

    // 🎯 任務開始時：不取消任何通知，只記錄開始事件
  }

  // 🎯 已移除：任務完成提醒通知功能
  // 不再需要，因為用戶可以手動標記任務完成

  Future<void> stopEvent(String uid, EventModel e) async {
    // 🎯 設置為暫停狀態（保留開始時間）並增加暫停次數
    final ref = await DataPathService.instance.getEventDocAuto(uid, e.id);
    final now = DateTime.now();

    // 获取当前暫停次數並增加1
    final snap = await ref.get();
    int currentPauseCount = 0;
    
    // 檢查文檔是否存在，避免 null 轉換錯誤
    if (snap.exists) {
      final data = snap.data() as Map<String, dynamic>?;
      if (data != null && data.containsKey('pauseCount')) {
        currentPauseCount = (data['pauseCount'] as int?) ?? 0;
      }
    }

    await ref.set({
      'status': TaskStatus.paused.value,  // 設置為暫停狀態
      'pauseCount': currentPauseCount + 1, // 增加暫停次數
      'pauseAt': Timestamp.fromDate(now), // 🎯 新增：記錄暫停時間
      'updatedAt': Timestamp.fromDate(now), // 更新時間
    }, SetOptions(merge: true));

    // 🎯 已移除：取消任務完成提醒通知
    // 不再需要，因為已移除該功能
  }

  Future<void> continueEvent(String uid, EventModel e) async {
    // 🎯 恢復任務：從暫停狀態恢復到進行中或超時狀態
    final ref = await DataPathService.instance.getEventDocAuto(uid, e.id);
    final now = DateTime.now();

    // 🎯 修复：正确处理暂停后继续的状态判断
    TaskStatus newStatus;
    if (e.actualStartTime != null && e.pauseAt != null) {
      // 如果任务有暂停时间，需要调整结束时间
      // 原定任务时长
      final originalTaskDuration = e.scheduledEndTime.difference(e.scheduledStartTime);
      // 已经工作的时间
      final workedDuration = e.pauseAt!.difference(e.actualStartTime!);
      // 剩余工作时间
      final remainingWorkDuration = originalTaskDuration - workedDuration;
      // 调整后的结束时间 = 继续时间 + 剩余工作时间
      final adjustedEndTime = now.add(remainingWorkDuration);
      
      // 由于我们刚刚继续任务，现在应该是在进行中状态
      newStatus = TaskStatus.inProgress;
      
      if (kDebugMode) {
        print('continueEvent: 暂停后继续 ${e.title}, 已工作时间: ${workedDuration.inMinutes}分钟, 剩余工作时间: ${remainingWorkDuration.inMinutes}分钟, 继续时间: $now, 调整后结束时间: $adjustedEndTime');
      }
    } else if (e.actualStartTime != null) {
      // 没有暂停时间，使用原来的逻辑
      final taskDuration = e.scheduledEndTime.difference(e.scheduledStartTime);
      final dynamicEndTime = e.actualStartTime!.add(taskDuration);
      newStatus = now.isAfter(dynamicEndTime) ? TaskStatus.overtime : TaskStatus.inProgress;
    } else {
      // 如果沒有實際開始時間，設為進行中
      newStatus = TaskStatus.inProgress;
    }

    await ref.set({
      'status': newStatus.value,
      'resumeAt': Timestamp.fromDate(now), // 🎯 新增：記錄繼續時間
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));

    // 🎯 任務恢復時：不取消任何通知，只更新狀態
  }

  Future<void> completeEvent(String uid, EventModel e) async {
    // 🎯 實驗數據收集：記錄任務完成（包含isDone, completedTime, updatedAt）
    await ExperimentEventHelper.recordEventCompletion(
      uid: uid,
      eventId: e.id,
      chatId: e.chatId,
    );
  }

  /// 更新事件狀態（用於同步時檢查overdue/notStarted狀態）
  Future<void> _updateEventStatuses(String uid, List<EventModel> events, DateTime now) async {
    try {
      // 使用 DataPathService 获取当前日期的 events 集合
      final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, now);
      final batch = FirebaseFirestore.instance.batch();
      bool hasBatchUpdates = false;

      for (final event in events) {
        // 🎯 修正：優先檢查 isDone 狀態，已完成任務不更新狀態
        if (event.isDone) {
          if (kDebugMode) {
            print('_updateEventStatuses: 跳過已完成任務: ${event.title}');
          }
          continue;
        }

        TaskStatus newStatus;
        
        if (event.actualStartTime != null) {
          // 🎯 修复关键bug：如果任务已被暂停，保持暂停状态，不要强制改为进行中
          if (event.status == TaskStatus.paused) {
            // 保持暂停状态，不更新
            if (kDebugMode) {
              print('_updateEventStatuses: 保持暂停状态: ${event.title}');
            }
            continue;
          }
          
          // 任務已開始但未完成，且未被暂停 → 判断是进行中还是超时
          final taskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
          final dynamicEndTime = event.actualStartTime!.add(taskDuration);
          
          if (now.isAfter(dynamicEndTime)) {
            newStatus = TaskStatus.overtime;
          } else {
            newStatus = TaskStatus.inProgress;
          }
        } else {
          // 🎯 修正：任務未開始時，需要檢查是否真的未開始
          // 如果任務有 completedTime，說明任務已完成，不應該被標記為 notStarted
          if (event.completedTime != null) {
            if (kDebugMode) {
              print('_updateEventStatuses: 跳過已完成任務（有 completedTime）: ${event.title}');
            }
            continue;
          }
          
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
          final ref = eventsCollection.doc(event.id);

          batch.update(ref, {
            'status': newStatus.value,
            'updatedAt': Timestamp.fromDate(now),
          });
          
          hasBatchUpdates = true;
          
          if (kDebugMode) {
            print('_updateEventStatuses: 更新事件狀態: ${event.title} -> ${newStatus.name}');
          }
        } else {
          if (kDebugMode && event.status == TaskStatus.paused) {
            print('_updateEventStatuses: 保持暂停状态: ${event.title}');
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
    } catch (e) {
      if (kDebugMode) {
        print('_updateEventStatuses: 更新事件狀態失敗: $e');
      }
      rethrow;
    }
  }

  // 🎯 已移除：取消任務完成提醒通知方法
  // 不再需要，因為已移除該功能
}
