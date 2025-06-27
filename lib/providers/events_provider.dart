import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';

class EventsProvider extends ChangeNotifier {
  Stream<List<EventModel>>? _stream;
  Stream<List<EventModel>>? get stream => _stream;
  DateTime? _currentDate;

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
    final end = start.add(const Duration(days: 1));
    final startTs = Timestamp.fromDate(start.toUtc());
    final endTs = Timestamp.fromDate(end.toUtc());

    _stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('events')
        .where('startTime', isGreaterThanOrEqualTo: startTs)
        .where('startTime', isLessThan: endTs)
        .orderBy('startTime')
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
