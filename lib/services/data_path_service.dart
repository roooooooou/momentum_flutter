import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:momentum/services/experiment_config_service.dart';
import 'day_number_service.dart';
import 'package:flutter/foundation.dart'; // Added for kDebugMode

/// 统一管理所有Firestore数据路径，根据用户分组返回正确的路径
class DataPathService {
  static final DataPathService instance = DataPathService._();
  DataPathService._();

  final _firestore = FirebaseFirestore.instance;

  /// 获取用户分组名称（新版：以週為單位，支援 RC 覆寫）
  Future<String> getUserGroupName(String uid) async {
    return await ExperimentConfigService.instance.getWeekGroupName(uid);
  }

  /// 获取指定日期的用户分组名称（暫保留：回退到舊的 date-based）
  Future<String> getDateGroupName(String uid, DateTime date) async {
    return await ExperimentConfigService.instance.getDateGroup(uid, date);
  }

  /// 取得 w0 事件集合引用（week0: day0 測試週）
  Future<CollectionReference> getUserW0EventsCollection(String uid) async {
    return _firestore.collection('users').doc(uid).collection('w0');
  }

  /// 取得 w1 事件集合引用（week1: day1~7）
  Future<CollectionReference> getUserW1EventsCollection(String uid) async {
    return _firestore.collection('users').doc(uid).collection('w1');
  }

  /// 取得 w2 事件集合引用（week2: day8+）
  Future<CollectionReference> getUserW2EventsCollection(String uid) async {
    return _firestore.collection('users').doc(uid).collection('w2');
  }

  /// 获取用户事件集合引用（基于當前日期所屬週：w1/w2）
  Future<CollectionReference> getUserEventsCollection(String uid) async {
    final today = DateTime.now();
    return await getDateEventsCollection(uid, today);
  }

  /// 获取指定日期的事件集合引用（依 dayNumber 判斷 w0/w1/w2）
  /// d0=測試天→w0, d1-d7=w1, d8+=w2
  Future<CollectionReference> getDateEventsCollection(String uid, DateTime date) async {
    final dayNum = await DayNumberService().calculateDayNumber(date);
    String folder;
    CollectionReference collection;
    
    if (dayNum == 0) {
      folder = 'w0';
      collection = await getUserW0EventsCollection(uid);
    } else if (dayNum >= 1 && dayNum <= 7) {
      folder = 'w1';
      collection = await getUserW1EventsCollection(uid);
    } else {
      folder = 'w2';
      collection = await getUserW2EventsCollection(uid);
    }
    
    // 🎯 調試：輸出日期與目標資料夾的詳細信息
    if (kDebugMode) {
      print('🎯 DataPathService.getDateEventsCollection:');
      print('🎯 uid: $uid');
      print('🎯 date: ${date.toIso8601String()}');
      print('🎯 dayNum: $dayNum');
      print('🎯 folder: $folder');
      print('🎯 collection path: ${collection.path}');
    }
    
    return collection;
  }

  /// 获取用户事件文档引用（基于当前日期）
  Future<DocumentReference> getUserEventDoc(String uid, String eventId) async {
    final eventsCol = await getUserEventsCollection(uid);
    return eventsCol.doc(eventId);
  }

  /// 優先在 w0/w1/w2 三個集合中查找已存在的事件文檔
  Future<DocumentReference?> findExistingEventDoc(String uid, String eventId) async {
    // 先檢查 w0（測試週）
    final w0Col = await getUserW0EventsCollection(uid);
    final w0Doc = w0Col.doc(eventId);
    final w0Snap = await w0Doc.get();
    if (w0Snap.exists) return w0Doc;

    // 再檢查 w1
    final w1Col = await getUserW1EventsCollection(uid);
    final w1Doc = w1Col.doc(eventId);
    final w1Snap = await w1Doc.get();
    if (w1Snap.exists) return w1Doc;

    // 最後檢查 w2
    final w2Col = await getUserW2EventsCollection(uid);
    final w2Doc = w2Col.doc(eventId);
    final w2Snap = await w2Doc.get();
    if (w2Snap.exists) return w2Doc;

    return null;
  }

  /// 自動解析事件所在集合（若找不到則回退到「當天分組」集合）
  Future<DocumentReference> getEventDocAuto(String uid, String eventId) async {
    final existing = await findExistingEventDoc(uid, eventId);
    if (existing != null) return existing;
    return await getUserEventDoc(uid, eventId);
  }

  /// 获取指定日期的事件文档引用
  Future<DocumentReference> getDateEventDoc(String uid, String eventId, DateTime date) async {
    if (kDebugMode) {
      print('🎯 DataPathService.getDateEventDoc 開始');
      print('🎯 uid: $uid');
      print('🎯 eventId: $eventId');
      print('🎯 date: ${date.toIso8601String()}');
    }
    
    final eventsCol = await getDateEventsCollection(uid, date);
    
    if (kDebugMode) {
      print('🎯 事件集合路徑: ${eventsCol.path}');
    }
    
    final eventDoc = eventsCol.doc(eventId);
    
    if (kDebugMode) {
      print('🎯 事件文檔路徑: ${eventDoc.path}');
      print('🎯 DataPathService.getDateEventDoc 完成');
    }
    
    return eventDoc;
  }

  /// 获取事件聊天集合引用（基于当前日期）
  Future<CollectionReference> getUserEventChatsCollection(String uid, String eventId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('chats');
  }

  /// 获取指定日期的事件聊天集合引用
  Future<CollectionReference> getDateEventChatsCollection(String uid, String eventId, DateTime date) async {
    final eventDoc = await getDateEventDoc(uid, eventId, date);
    return eventDoc.collection('chats');
  }

  /// 获取用户事件聊天文档引用（基于当前日期）
  Future<DocumentReference> getUserEventChatDoc(String uid, String eventId, String chatId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('chats').doc(chatId);
  }

  /// 获取指定日期的事件聊天文档引用
  Future<DocumentReference> getDateEventChatDoc(String uid, String eventId, String chatId, DateTime date) async {
    final eventDoc = await getDateEventDoc(uid, eventId, date);
    return eventDoc.collection('chats').doc(chatId);
  }

  /// 自動解析事件聊天文檔引用
  Future<DocumentReference> getEventChatDocAuto(String uid, String eventId, String chatId) async {
    final eventDoc = await getEventDocAuto(uid, eventId);
    return eventDoc.collection('chats').doc(chatId);
  }

  /// 自動解析事件聊天集合引用
  Future<CollectionReference> getEventChatsCollectionAuto(String uid, String eventId) async {
    final eventDoc = await getEventDocAuto(uid, eventId);
    return eventDoc.collection('chats');
  }

  /// 获取事件通知集合引用（基于当前日期）
  Future<CollectionReference> getUserEventNotificationsCollection(String uid, String eventId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('notifications');
  }

  /// 获取指定日期的事件通知集合引用
  Future<CollectionReference> getDateEventNotificationsCollection(String uid, String eventId, DateTime date) async {
    final eventDoc = await getDateEventDoc(uid, eventId, date);
    return eventDoc.collection('notifications');
  }

  /// 获取事件通知文档引用（基于当前日期）
  Future<DocumentReference> getUserEventNotificationDoc(String uid, String eventId, String notifId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('notifications').doc(notifId);
  }

  /// 获取指定日期的事件通知文档引用
  Future<DocumentReference> getDateEventNotificationDoc(String uid, String eventId, String notifId, DateTime date) async {
    if (kDebugMode) {
      print('🎯 DataPathService.getDateEventNotificationDoc 開始');
      print('🎯 uid: $uid');
      print('🎯 eventId: $eventId');
      print('🎯 notifId: $notifId');
      print('🎯 date: ${date.toIso8601String()}');
    }
    
    final eventDoc = await getDateEventDoc(uid, eventId, date);
    
    if (kDebugMode) {
      print('🎯 事件文檔路徑: ${eventDoc.path}');
    }
    
    final notifDoc = eventDoc.collection('notifications').doc(notifId);
    
    if (kDebugMode) {
      print('🎯 通知文檔路徑: ${notifDoc.path}');
      print('🎯 DataPathService.getDateEventNotificationDoc 完成');
    }
    
    return notifDoc;
  }

  /// 获取用户Sessions集合引用
  Future<CollectionReference> getUserSessionsCollection(String uid) async {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('sessions');
  }

  /// 获取用户App Session文档引用
  Future<DocumentReference> getUserSessionDoc(String uid, String sessionId) async {
    final sessionsCollection = await getUserSessionsCollection(uid);
    return sessionsCollection.doc(sessionId);
  }

  /// 获取用户Daily Metrics集合引用
  Future<CollectionReference> getUserDailyMetricsCollection(String uid) async {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('daily_metrics');
  }

  /// 获取特定日期的Daily Metrics文档引用
  Future<DocumentReference> getUserDailyMetricsDoc(String uid, String date) async {
    final metricsCollection = await getUserDailyMetricsCollection(uid);
    return metricsCollection.doc(date);
  }

  /// 获取Daily Report集合引用（存储在daily_metrics下）
  Future<CollectionReference> getUserDailyReportCollection(String uid, String date) async {
    final metricsDoc = await getUserDailyMetricsDoc(uid, date);
    return metricsDoc.collection('daily_report');
  }

  /// 获取用户分组（基于当前日期）
  Future<ExperimentGroup> getUserGroup(String uid) async {
    final today = DateTime.now();
    final groupName = await getDateGroupName(uid, today);
    return groupName == 'control' ? ExperimentGroup.control : ExperimentGroup.experiment;
  }

  /// 获取指定日期的用户分组
  Future<ExperimentGroup> getDateGroup(String uid, DateTime date) async {
    final groupName = await getDateGroupName(uid, date);
    return groupName == 'control' ? ExperimentGroup.control : ExperimentGroup.experiment;
  }

  /// 判断用户是否在对照组（基于当前日期）
  Future<bool> isControlGroup(String uid) async {
    final group = await getUserGroup(uid);
    return group == ExperimentGroup.control;
  }

  /// 判断指定日期用户是否在对照组
  Future<bool> isDateControlGroup(String uid, DateTime date) async {
    final group = await getDateGroup(uid, date);
    return group == ExperimentGroup.control;
  }

  /// 获取所有事件集合（w0 + w1 + w2）
  Future<List<CollectionReference>> getAllEventsCollections(String uid) async {
    return [
      await getUserW0EventsCollection(uid),
      await getUserW1EventsCollection(uid),
      await getUserW2EventsCollection(uid),
    ];
  }

  /// 根據 dayNumber 取得事件集合（d0=測試天→w0, d1-d7→w1，d8+→w2）
  Future<CollectionReference> getEventsCollectionByDayNumber(String uid, int dayNumber) async {
    if (dayNumber == 0) {
      return await getUserW0EventsCollection(uid);
    } else if (dayNumber >= 1 && dayNumber <= 6) {
      return await getUserW1EventsCollection(uid);
    } else {
      return await getUserW2EventsCollection(uid);
    }
  }

  /// 保留舊接口：根據日期與（舊）組別取得事件集合
  /// 已不再使用 experiment/control，會回退到依日期的 w1/w2
  Future<CollectionReference> getEventsCollectionByGroup(String uid, String group, {DateTime? date}) async {
    return await getDateEventsCollection(uid, date ?? DateTime.now());
  }
} 