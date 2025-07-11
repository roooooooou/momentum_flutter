import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';

/// 事件提供者：只顯示當天的事件
/// 注意：雖然CalendarService同步未來一週的事件到Firebase，
/// 但此Provider只查詢並顯示當天的事件
class EventsProvider extends ChangeNotifier {
  Stream<List<EventModel>>? _stream;
  Stream<List<EventModel>>? get stream => _stream;
  DateTime? _currentDate;

  /// 設置用戶並建立當天事件的Stream
  /// 注意：只查詢當天事件，即使Firebase中有未來一週的事件
  void setUser(User? user) {
    if (user == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 如果是同一天，且已經有 stream，就不需要重新設置
    if (_currentDate != null && 
        _currentDate!.year == today.year && 
        _currentDate!.month == today.month && 
        _currentDate!.day == today.day &&
        _stream != null) {
      return;
    }
    
    _currentDate = today;
    final start = today;
    final end = start.add(const Duration(days: 1)); // 只查詢當天，不是一週
    final startTs = Timestamp.fromDate(start.toUtc());
    final endTs = Timestamp.fromDate(end.toUtc());

    _stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('events')
        .where('scheduledStartTime', isGreaterThanOrEqualTo: startTs)
        .where('scheduledStartTime', isLessThan: endTs)
        .orderBy('scheduledStartTime')
        .snapshots()
        .map((q) => q.docs.map(EventModel.fromDoc).toList());

    notifyListeners();
  }
  
  /// 強制刷新當天事件（用於跨日處理）
  void refreshToday(User? user) {
    _currentDate = null; // 重置日期緩存
    setUser(user);
  }
}
