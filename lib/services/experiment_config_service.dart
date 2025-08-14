import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'day_number_service.dart';

/// 实验组类型
enum ExperimentGroup {
  control(0),      // 对照组
  experiment(1);   // 实验组

  const ExperimentGroup(this.value);
  final int value;

  static ExperimentGroup fromValue(int value) {
    try {
      return ExperimentGroup.values.firstWhere(
        (group) => group.value == value,
        orElse: () => ExperimentGroup.experiment, // 默认实验组
      );
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentGroup: 无效的值 $value，使用默认实验组');
      }
      return ExperimentGroup.experiment;
    }
  }
}

/// 实验配置服务
/// 管理基于日期的用户分组逻辑
class ExperimentConfigService {
  ExperimentConfigService._();
  static final instance = ExperimentConfigService._();

  final _firestore = FirebaseFirestore.instance;
  /// 簡化：直接根據 manual_week_assignment 與當日屬於 w1/w2 映射為 experiment/control
  Future<ExperimentGroup> getUserGroup(String uid) async {
    final groupName = await getWeekGroupName(uid);
    return groupName == 'control' ? ExperimentGroup.control : ExperimentGroup.experiment;
  }

  // 舊的日期分組流程已移除

  /// 新：以週為單位的組別判定（僅使用 Firestore 的 manual_week_assignment: 'A'|'B'）
  /// dayNumber 0-7 → w1，>7 → w2；'A': w1=experiment, w2=control；'B': w1=control, w2=experiment
  Future<String> getWeekGroupName(String uid) async {
    try {
      final manual = await _getManualWeekAssignment(uid); // 'A'|'B'|null
      final assign = manual ?? 'A';
      final dayNum = await DayNumberService().getTodayDayNumber();
      final isWeek1 = dayNum <= 7;
      if (assign == 'A') {
        return isWeek1 ? 'experiment' : 'control';
      } else {
        return isWeek1 ? 'control' : 'experiment';
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService.getWeekGroupName error: $e');
      }
      return 'experiment';
    }
  }

  /// 新：以週為單位（指定日期版，僅使用 manual_week_assignment）
  Future<String> getWeekGroupNameForDate(String uid, DateTime date) async {
    try {
      final manual = await _getManualWeekAssignment(uid); // 'A'|'B'|null
      final assign = manual ?? 'A';
      final dayNum = await DayNumberService().calculateDayNumber(date);
      final isWeek1 = dayNum <= 7;
      if (assign == 'A') {
        return isWeek1 ? 'experiment' : 'control';
      } else {
        return isWeek1 ? 'control' : 'experiment';
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService.getWeekGroupNameForDate error: $e');
      }
      return 'experiment';
    }
  }

  /// 取得指定日期的組別（已改為以週為單位的週分派邏輯）
  Future<String> getDateGroup(String uid, DateTime date) async {
    return await getWeekGroupNameForDate(uid, date);
  }

  /// 讀取 Firestore 手動週分派（A/B），若不存在則回傳 null
  Future<String?> _getManualWeekAssignment(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      final v = data['manual_week_assignment']; // 'A' or 'B'
      if (v is String && (v == 'A' || v == 'B')) return v;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 設定 Firestore 手動週分派（傳 null 代表清除手動設定，改回 RC）
  Future<void> setManualWeekAssignment(String uid, String? assignment) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      if (assignment == null || assignment.isEmpty) {
        await userRef.update({'manual_week_assignment': FieldValue.delete()});
      } else {
        final v = (assignment == 'B') ? 'B' : 'A';
        await userRef.set({'manual_week_assignment': v}, SetOptions(merge: true));
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService.setManualWeekAssignment failed: $e');
      }
      rethrow;
    }
  }

  /// 檢查是否為實驗組（以今日週分派）
  Future<bool> isExperimentGroup(String uid) async {
    final today = DateTime.now();
    final group = await getDateGroup(uid, today);
    return group == 'experiment';
  }

  /// 檢查是否為對照組（以今日週分派）
  Future<bool> isControlGroup(String uid) async {
    final today = DateTime.now();
    final group = await getDateGroup(uid, today);
    return group == 'control';
  }

  // 舊的日期分組流程已移除

  // 舊的日期分組流程已移除

  // 舊的日期分組流程已移除
} 