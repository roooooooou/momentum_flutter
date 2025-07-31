import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:momentum/services/experiment_config_service.dart';

/// 统一管理所有Firestore数据路径，根据用户分组返回正确的路径
class DataPathService {
  static final DataPathService instance = DataPathService._();
  DataPathService._();

  final _firestore = FirebaseFirestore.instance;

  /// 获取用户分组名称（基于当前日期）
  Future<String> getUserGroupName(String uid) async {
    final today = DateTime.now();
    return await ExperimentConfigService.instance.getDateGroup(uid, today);
  }

  /// 获取指定日期的用户分组名称
  Future<String> getDateGroupName(String uid, DateTime date) async {
    return await ExperimentConfigService.instance.getDateGroup(uid, date);
  }

  /// 获取用户实验组事件集合引用
  Future<CollectionReference> getUserExperimentEventsCollection(String uid) async {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('experiment_events');
  }

  /// 获取用户对照组事件集合引用
  Future<CollectionReference> getUserControlEventsCollection(String uid) async {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('control_events');
  }

  /// 获取用户事件集合引用（基于当前日期）
  Future<CollectionReference> getUserEventsCollection(String uid) async {
    final group = await getUserGroupName(uid);
    return group == 'experiment' 
        ? await getUserExperimentEventsCollection(uid)
        : await getUserControlEventsCollection(uid);
  }

  /// 获取指定日期的事件集合引用
  Future<CollectionReference> getDateEventsCollection(String uid, DateTime date) async {
    final group = await getDateGroupName(uid, date);
    return group == 'experiment' 
        ? await getUserExperimentEventsCollection(uid)
        : await getUserControlEventsCollection(uid);
  }

  /// 获取用户事件文档引用（基于当前日期）
  Future<DocumentReference> getUserEventDoc(String uid, String eventId) async {
    final eventsCol = await getUserEventsCollection(uid);
    return eventsCol.doc(eventId);
  }

  /// 获取指定日期的事件文档引用
  Future<DocumentReference> getDateEventDoc(String uid, String eventId, DateTime date) async {
    final eventsCol = await getDateEventsCollection(uid, date);
    return eventsCol.doc(eventId);
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
    final eventDoc = await getDateEventDoc(uid, eventId, date);
    return eventDoc.collection('notifications').doc(notifId);
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

  /// 获取所有事件集合（实验组和对照组）
  Future<List<CollectionReference>> getAllEventsCollections(String uid) async {
    return [
      await getUserExperimentEventsCollection(uid),
      await getUserControlEventsCollection(uid),
    ];
  }

  /// 根据日期和组别获取事件集合
  Future<CollectionReference> getEventsCollectionByGroup(String uid, String group) async {
    return group == 'experiment' 
        ? await getUserExperimentEventsCollection(uid)
        : await getUserControlEventsCollection(uid);
  }
} 