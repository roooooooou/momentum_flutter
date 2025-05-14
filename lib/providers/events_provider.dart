import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';

class EventsProvider extends ChangeNotifier {
  Stream<List<EventModel>>? _stream;
  Stream<List<EventModel>>? get stream => _stream;

  void setUser(User? user) {
    if (user == null) return;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
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
}
