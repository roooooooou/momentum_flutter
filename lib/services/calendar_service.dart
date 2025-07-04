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

  /// 強制完整同步今日事件（手動觸發）
  Future<void> forceSyncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('手動觸發完整同步');
    }
    
    try {
      await syncToday(uid);
    } catch (e) {
      // 確保在錯誤時也重置同步狀態
      _setSyncingState(false);
      rethrow;
    }
  }

  /// App Resume 同步
  Future<void> resumeSync(String uid) async {
    if (kDebugMode) {
      print('App Resume: 開始同步');
    }
    
    try {
      // 直接使用 syncToday，因為邏輯完全一樣
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

  /// Syncs today's events from *primary* calendar into Firestore `/events`.
  Future<void> syncToday(String uid) async {
    if (_isSyncing) return; // 防止重複同步
    
    if (kDebugMode) {
      print('syncToday: 開始同步，UID: $uid');
    }
    
    _setSyncingState(true);
    try {
      await _ensureReady();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 1));

      if (kDebugMode) {
        print('syncToday: 查詢 Google Calendar 事件，時間範圍: $start 到 $end');
      }

      final apiEvents = await _api!.events.list(
        'primary',
        timeMin: start,
        timeMax: end,
        singleEvents: true,
        orderBy: 'startTime',
      );

      if (kDebugMode) {
        print('syncToday: 從 Google Calendar 獲取到 ${apiEvents!.items?.length ?? 0} 個事件');
      }

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events');

      final idsToday = <String>{};

      // 1) 逐筆 upsert
      for (final e in apiEvents!.items ?? <cal.Event>[]) {
        final s = e.start?.dateTime, t = e.end?.dateTime;
        if (s == null || t == null) continue;

        final ref = col.doc(e.id);
        final snap = await ref.get(); // 先判斷有沒有這筆

        final data = <String, dynamic>{
          'title': e.summary ?? 'No title',
          'scheduledStartTime': Timestamp.fromDate(s.toUtc()), // 實驗數據用
          'scheduledEndTime': Timestamp.fromDate(t.toUtc()),
          'googleEventId': e.id,
          'googleCalendarId': e.organizer?.email ?? 'primary',
          'updatedAt': Timestamp.fromDate(e.updated?.toUtc() ?? now.toUtc()), // 向後兼容
          if (!snap.exists) 'isDone': false, // 向後兼容
          if (!snap.exists) 'createdAt': Timestamp.fromDate(now.toUtc()), // 實驗數據用
        };

        await ref.set(data, SetOptions(merge: true));
        idsToday.add(e.id!);
        
        if (kDebugMode) {
          print('syncToday: 同步事件: ${e.summary} (ID: ${e.id})');
        }
      }

      // 2) 移除 Google 已刪除的事件
      final snap = await col
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .get();

      final batch = FirebaseFirestore.instance.batch();
      final deletedEvents = <String>[];
      
      if (kDebugMode) {
        print('syncToday: API 返回的事件 ID: ${idsToday.toList()}');
        print('syncToday: 本地事件數量: ${snap.docs.length}');
      }
      
      for (final d in snap.docs) {
        if (kDebugMode) {
          print('syncToday: 檢查本地事件: ${d.data()['title']} (ID: ${d.id})');
        }
        
        if (!idsToday.contains(d.id)) {
          // 在刪除前取消通知
          final data = d.data();
          final notifIds = (data['notifIds'] as List<dynamic>?)?.cast<String>() ?? [];
          if (notifIds.isNotEmpty) {
            await NotificationScheduler().cancelEventNotification(d.id, notifIds);
          }
          
          batch.delete(d.reference);
          deletedEvents.add(d.id);
          if (kDebugMode) {
            print('syncToday: 刪除事件: ${data['title']} (ID: ${d.id})');
          }
        } else {
          if (kDebugMode) {
            print('syncToday: 保留事件: ${d.data()['title']} (ID: ${d.id})');
          }
        }
      }
      
      if (deletedEvents.isNotEmpty) {
        await batch.commit();
        if (kDebugMode) {
          print('syncToday: 已刪除 ${deletedEvents.length} 個事件');
        }
      }
      
      // 3) 重新讀取今日所有事件，用於通知排程
      final updatedSnap = await col
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final events = updatedSnap.docs.map(EventModel.fromDoc).toList();
      
      // 4) 更新任務狀態（檢查overdue/notStarted）
      if (events.isNotEmpty) {
        await _updateEventStatuses(uid, events, now);
        if (kDebugMode) {
          print('syncToday: 更新了 ${events.length} 個事件的狀態');
        }
      }

      // 5) 同步通知排程
      if (events.isNotEmpty) {
        await NotificationScheduler().sync(events);
        if (kDebugMode) {
          print('syncToday: 同步了 ${events.length} 個事件的通知排程');
        }
      }
      
      // 更新並儲存lastSyncAt
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
}
