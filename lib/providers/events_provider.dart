import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';
import '../services/data_path_service.dart';

/// 事件提供者：只显示当天的活跃事件
/// 注意：虽然CalendarService同步未来一周的事件到Firebase，
/// 但此Provider只查询并显示当天的活跃事件（过滤已归档的事件）
class EventsProvider extends ChangeNotifier {
  Stream<List<EventModel>>? _stream;
  Stream<List<EventModel>>? get stream => _stream;
  DateTime? _currentDate;

  /// 设置用户并建立当天活跃事件的Stream
  /// 注意：只查询当天的活跃事件，过滤已删除/移动的事件
  void setUser(User? user) {
    if (user == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 如果是同一天，且已经有 stream，就不需要重新设置
    if (_currentDate != null && 
        _currentDate!.year == today.year && 
        _currentDate!.month == today.month && 
        _currentDate!.day == today.day &&
        _stream != null) {
      return;
    }
    
    _currentDate = today;
    
    // 修复时区问题：使用台湾时区计算今天的范围
    final localToday = today; // 本地午夜
    final localTomorrow = localToday.add(const Duration(days: 1)); // 本地明天午夜
    
    // 转换为UTC用于Firestore查询
    final start = localToday; // 只查询当天，不是一周
    final end = localTomorrow;
    final startTs = Timestamp.fromDate(start.toUtc());
    final endTs = Timestamp.fromDate(end.toUtc());

    // 使用 DataPathService 获取正确的事件路径
    _setupEventStream(user.uid, startTs, endTs);
    
    notifyListeners();
  }

  /// 设置事件Stream（异步获取路径）
  void _setupEventStream(String uid, Timestamp startTs, Timestamp endTs) async {
    try {
      // 先取消现有的stream
      _stream = null;
      notifyListeners();
      
      // 获取当前日期的events集合引用
      final now = DateTime.now();
      final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, now);
      
      // 构建查询：只获取活跃事件（未被删除或移动的事件）
      _stream = eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: startTs)
          .where('scheduledStartTime', isLessThan: endTs)
          .orderBy('scheduledStartTime')
          .snapshots()
          .map((q) => q.docs
              .map(EventModel.fromDoc)
              .where((event) => event.isActive) // 只显示活跃事件
              .toList());

      notifyListeners();
    } catch (e) {
      print('EventsProvider: 设置事件Stream失败: $e');
      // 如果出错，设置空Stream
      _stream = Stream.value(<EventModel>[]);
      notifyListeners();
    }
  }
  
  /// 强制刷新当天事件（用于跨日处理）
  void refreshToday(User? user) {
    _currentDate = null; // 重置日期缓存
    setUser(user);
  }

  /// 获取已归档事件的Stream（用于调试或历史查看）
  Stream<List<EventModel>> getArchivedEventsStream(User user, {int days = 7}) async* {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
    final end = DateTime(now.year, now.month, now.day).add(Duration(days: days));
    final startTs = Timestamp.fromDate(start.toUtc());
    final endTs = Timestamp.fromDate(end.toUtc());

    try {
      // 使用 DataPathService 获取当前日期的路径
      final eventsCollection = await DataPathService.instance.getDateEventsCollection(user.uid, now);
      
      // 使用简单查询，避免复合索引问题
      final query = eventsCollection
          .where('archivedAt', isGreaterThanOrEqualTo: startTs)
          .where('archivedAt', isLessThanOrEqualTo: endTs);
      
      final snapshot = await query.get();
      final events = snapshot.docs
          .map(EventModel.fromDoc)
          .where((event) => event.isArchived) // 在内存中过滤已归档事件
          .toList()
        ..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!)); // 按时间排序
      
      yield events;
    } catch (e) {
      print('EventsProvider: 获取归档事件失败: $e');
      yield <EventModel>[];
    }
  }
}
