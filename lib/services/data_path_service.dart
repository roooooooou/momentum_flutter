import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:momentum/models/enums.dart';
import 'package:momentum/services/experiment_config_service.dart';

/// 统一管理所有Firestore数据路径，根据用户分组返回正确的路径
class DataPathService {
  static final DataPathService instance = DataPathService._();
  DataPathService._();

  final _firestore = FirebaseFirestore.instance;

  /// 获取用户分组名称
  Future<String> getUserGroupName(String uid) async {
    final group = await getUserGroup(uid);
    return group == ExperimentGroup.control ? 'control' : 'experiment';
  }

  /// 获取用户事件集合引用
  Future<CollectionReference> getUserEventsCollection(String uid) async {
    final group = await getUserGroup(uid);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection(group.name)
        .doc('data')
        .collection('events');
  }

  /// 获取用户事件文档引用
  Future<DocumentReference> getUserEventDoc(String uid, String eventId) async {
    final eventsCol = await getUserEventsCollection(uid);
    return eventsCol.doc(eventId);
  }

  /// 获取事件聊天集合引用
  Future<CollectionReference> getUserEventChatsCollection(String uid, String eventId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('chats');
  }

  /// 获取用户事件聊天文档引用
  Future<DocumentReference> getUserEventChatDoc(String uid, String eventId, String chatId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('chats').doc(chatId);
  }

  /// 获取事件通知集合引用
  Future<CollectionReference> getUserEventNotificationsCollection(String uid, String eventId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('notifications');
  }

  /// 获取事件通知文档引用
  Future<DocumentReference> getUserEventNotificationDoc(String uid, String eventId, String notifId) async {
    final eventDoc = await getUserEventDoc(uid, eventId);
    return eventDoc.collection('notifications').doc(notifId);
  }

  /// 获取用户App Sessions集合引用
  Future<CollectionReference> getUserAppSessionsCollection(String uid) async {
    final groupName = await getUserGroupName(uid);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection(groupName)
        .doc('data')
        .collection('app_sessions');
  }

  /// 获取用户App Session文档引用
  Future<DocumentReference> getUserAppSessionDoc(String uid, String sessionId) async {
    final sessionsCollection = await getUserAppSessionsCollection(uid);
    return sessionsCollection.doc(sessionId);
  }

  /// 获取用户Daily Metrics集合引用
  Future<CollectionReference> getUserDailyMetricsCollection(String uid) async {
    final groupName = await getUserGroupName(uid);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection(groupName)
        .doc('data')
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

  /// 获取用户分组
  Future<ExperimentGroup> getUserGroup(String uid) async {
    final configService = ExperimentConfigService.instance;
    return await configService.getUserGroup(uid);
  }

  /// 判断用户是否在对照组
  Future<bool> isControlGroup(String uid) async {
    final group = await getUserGroup(uid);
    return group == ExperimentGroup.control;
  }
} 