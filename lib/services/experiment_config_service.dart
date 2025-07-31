import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
  final Set<String> _processingUsers = {}; // 防止重复处理同一用户

  /// 获取用户的实验组配置
  /// 如果用户没有配置，会自动分配并保存
  Future<ExperimentGroup> getUserGroup(String uid) async {
    // 防止重复处理同一用户
    if (_processingUsers.contains(uid)) {
      if (kDebugMode) {
        print('ExperimentConfigService: 用户 $uid 正在处理中，跳过重复检测');
      }
      // 直接返回当前组别，不进行组别变化检测
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final data = userDoc.data()! as Map<String, dynamic>?;
          if (data != null && data.containsKey('date_based_grouping')) {
            return ExperimentGroup.experiment; // 如果已有日期分组配置，返回实验组
          }
        }
        return ExperimentGroup.experiment; // 默认返回实验组
      } catch (e) {
        return ExperimentGroup.experiment;
      }
    }

    _processingUsers.add(uid);
    
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (!userDoc.exists) {
        // 新用户，需要分配日期分组
        if (kDebugMode) {
          print('ExperimentConfigService: 新用户 $uid，开始分配日期分组');
        }
        return await _assignDateBasedGrouping(uid);
      }
      
      final data = userDoc.data()! as Map<String, dynamic>?;
      if (data == null) {
        if (kDebugMode) {
          print('ExperimentConfigService: 用户文档数据为空，分配日期分组');
        }
        return await _assignDateBasedGrouping(uid);
      }
      
      // 检查是否已有日期分组配置
      if (data.containsKey('date_based_grouping')) {
        if (kDebugMode) {
          print('ExperimentConfigService: 用户 $uid 已有日期分组配置');
        }
        return ExperimentGroup.experiment; // 有日期分组配置的用户都视为实验组
      }
      
      // 老用户，需要迁移到日期分组
      if (kDebugMode) {
        print('ExperimentConfigService: 老用户 $uid，迁移到日期分组');
      }
      return await _assignDateBasedGrouping(uid);
      
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 获取用户组别失败: $e');
      }
      return ExperimentGroup.experiment; // 出错时默认实验组
    } finally {
      _processingUsers.remove(uid);
    }
  }

  /// 为用户分配基于日期的分组
  Future<ExperimentGroup> _assignDateBasedGrouping(String uid) async {
    try {
      // 生成未来15天的日期分组
      final dateGroupings = await _generateDateGroupings(uid);
      
      // 保存日期分组配置
      await _saveDateBasedGrouping(uid, dateGroupings);
      
      if (kDebugMode) {
        print('ExperimentConfigService: 用户 $uid 日期分组分配完成');
        print('日期分组: $dateGroupings');
      }
      
      return ExperimentGroup.experiment; // 有日期分组配置的用户都视为实验组
      
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 分配日期分组失败: $e');
      }
      return ExperimentGroup.experiment; // 出错时默认实验组
    }
  }

  /// 生成未来15天的日期分组（使用台湾时区）
  Future<Map<String, String>> _generateDateGroupings(String uid) async {
    final dateGroupings = <String, String>{};
    final now = DateTime.now(); // 使用本地时区（台湾时区）
    
    // 基于UID生成确定性随机数
    final seed = uid.hashCode;
    final random = Random(seed);
    
    // 为未来15天的每一天分配组别
    for (int i = 0; i < 15; i++) {
      final date = now.add(Duration(days: i));
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      // 50%概率分配到实验组或对照组
      final group = random.nextBool() ? 'experiment' : 'control';
      dateGroupings[dateKey] = group;
    }
    
    return dateGroupings;
  }

  /// 保存日期分组配置
  Future<void> _saveDateBasedGrouping(String uid, Map<String, String> dateGroupings) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'date_based_grouping': dateGroupings,
        'date_grouping_created_at': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) {
        print('ExperimentConfigService: 日期分组配置已保存');
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 保存日期分组配置失败: $e');
      }
      rethrow;
    }
  }

  /// 获取指定日期的组别（使用台湾时区）
  Future<String> getDateGroup(String uid, DateTime date) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        return 'experiment'; // 默认实验组
      }
      
      final data = userDoc.data()! as Map<String, dynamic>?;
      if (data == null || !data.containsKey('date_based_grouping')) {
        return 'experiment'; // 默认实验组
      }
      
      final dateGroupings = Map<String, String>.from(data['date_based_grouping'] as Map);
      // 使用台湾时区生成日期键
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      return dateGroupings[dateKey] ?? 'experiment'; // 默认实验组
      
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 获取日期组别失败: $e');
      }
      return 'experiment'; // 默认实验组
    }
  }

  /// 检查用户是否为实验组（基于当前日期）
  Future<bool> isExperimentGroup(String uid) async {
    final today = DateTime.now();
    final group = await getDateGroup(uid, today);
    return group == 'experiment';
  }

  /// 检查用户是否为对照组（基于当前日期）
  Future<bool> isControlGroup(String uid) async {
    final today = DateTime.now();
    final group = await getDateGroup(uid, today);
    return group == 'control';
  }

  /// 获取实验配置统计信息（用于调试）
  Future<Map<String, dynamic>> getExperimentStats() async {
    try {
      final usersSnapshot = await _firestore.collection('users').get();
      int totalUsers = 0;
      int dateBasedUsers = 0;
      
      for (final doc in usersSnapshot.docs) {
        totalUsers++;
        final data = doc.data();
        if (data.containsKey('date_based_grouping')) {
          dateBasedUsers++;
        }
      }
      
      return {
        'total_users': totalUsers,
        'date_based_users': dateBasedUsers,
        'migration_progress': totalUsers > 0 ? dateBasedUsers / totalUsers : 0.0,
      };
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 获取统计信息失败: $e');
      }
      return {};
    }
  }
} 