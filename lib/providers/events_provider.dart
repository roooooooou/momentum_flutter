import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';
import '../services/data_path_service.dart';
import '../services/day_number_service.dart';

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

  /// 取得本週已發生(現在之前)的事件串流（Past Events）。
  /// 僅包含活躍事件，過濾測試事件，且依開始時間排序（新到舊）。
  /// 邏輯：d0=測試天(不包含), d1-d7=w1, d8+=w2
  /// 範例：今天是d3時，顯示d1,d2的事件；今天是d8時，不應有past events
  Stream<List<EventModel>> getPastEventsStream(User user) async* {
    try {
      final now = DateTime.now();
      // dayNumber 以 DayNumberService 計算
      final dayNumber = await DayNumberService().calculateDayNumber(now);
      
      print('🔍 getPastEventsStream: dayNumber = $dayNumber');
      
      // 🎯 關鍵修正：w2 第一天 (d8) 直接返回空陣列，不做任何查詢
      if (dayNumber == 8) {
        print('🔍 w2-d1: 直接返回空陣列，不查詢任何事件');
        yield <EventModel>[];
        return;
      }
      
      // d0 是測試天，d1 是第一天，所以 d1 也不應該有 past events
      if (dayNumber <= 1) {
        print('🔍 dayNumber <= 1: 返回空陣列');
        yield <EventModel>[];
        return;
      }
      
      final List<EventModel> all = [];
      
      if (dayNumber >= 2 && dayNumber <= 7) {
        print('🔍 w1 情況 (d$dayNumber)：查詢 d1 到 d${dayNumber-1} 的事件');
        // w1 情況：d2-d7，顯示 d1 到 dayNumber-1 的事件
        final w1Collection = await DataPathService.instance.getEventsCollectionByDayNumber(user.uid, dayNumber);
        
        // 只查詢前面天數的事件，不包含當天
        for (int d = 1; d < dayNumber; d++) {
          // 先嘗試使用 Firestore 查詢過濾 dayNumber
          var snap = await w1Collection
              .where('dayNumber', isEqualTo: d)
              .where('isActive', isEqualTo: true)
              .get();
          
          var items = snap.docs
              .map(EventModel.fromDoc)
              .where((e) => !_isTestEvent(e.title)) // 過濾測試事件
              .toList();
          
          // 如果沒有找到結果，可能是因為舊事件沒有 dayNumber 字段，嘗試備用查詢
          if (items.isEmpty) {
            print('🔍 w1 d$d: dayNumber 查詢無結果，嘗試備用查詢（查詢所有 isActive=true 事件並在記憶體過濾）');
            final fallbackSnap = await w1Collection
                .where('isActive', isEqualTo: true)
                .get();
            items = fallbackSnap.docs
                .map(EventModel.fromDoc)
                .where((e) => e.dayNumber == d) // 在記憶體中過濾
                .where((e) => !_isTestEvent(e.title)) // 過濾測試事件
                .toList();
          }
          
          print('🔍 w1 d$d: 找到 ${items.length} 個過去事件');
          all.addAll(items);
        }
      } else if (dayNumber > 8) {
        print('🔍 w2 其他天 (d$dayNumber)：查詢 d8 到 d${dayNumber-1} 的事件');
        // w2 其他天：顯示 d8 到 dayNumber-1 的事件
        final w2Collection = await DataPathService.instance.getEventsCollectionByDayNumber(user.uid, dayNumber);
        
        // 只查詢前面天數的事件，不包含當天
        for (int d = 8; d < dayNumber; d++) {
          // 先嘗試使用 Firestore 查詢過濾 dayNumber
          var snap = await w2Collection
              .where('dayNumber', isEqualTo: d)
              .where('isActive', isEqualTo: true)
              .get();
          
          var items = snap.docs
              .map(EventModel.fromDoc)
              .where((e) => !_isTestEvent(e.title)) // 過濾測試事件
              .toList();
          
          // 如果沒有找到結果，可能是因為舊事件沒有 dayNumber 字段，嘗試備用查詢
          if (items.isEmpty) {
            print('🔍 w2 d$d: dayNumber 查詢無結果，嘗試備用查詢（查詢所有 isActive=true 事件並在記憶體過濾）');
            final fallbackSnap = await w2Collection
                .where('isActive', isEqualTo: true)
                .get();
            items = fallbackSnap.docs
                .map(EventModel.fromDoc)
                .where((e) => e.dayNumber == d) // 在記憶體中過濾
                .where((e) => !_isTestEvent(e.title)) // 過濾測試事件
                .toList();
          }
          
          print('🔍 w2 d$d: 找到 ${items.length} 個過去事件');
          all.addAll(items);
        }
      }
      
      print('🔍 總共找到 ${all.length} 個 past events');
      // 依開始時間由新到舊排序
      all.sort((a, b) => b.scheduledStartTime.compareTo(a.scheduledStartTime));
      yield all;
    } catch (e) {
      print('EventsProvider: 獲取本週 Past Events 失敗: $e');
      yield <EventModel>[];
    }
  }

  /// 判斷是否為測試事件
  bool _isTestEvent(String title) {
    final lower = title.toLowerCase().trim();
    final vocabTest = RegExp(r'^vocab[-_]?w\d+[-_]?test$');
    final readingTest = RegExp(r'^reading[-_]?w\d+[-_]?test$');
    return vocabTest.hasMatch(lower) || readingTest.hasMatch(lower);
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
