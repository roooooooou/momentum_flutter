import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'remote_config_service.dart';
import 'notification_service.dart';
import '../models/event_model.dart';
import 'data_path_service.dart';

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
/// 管理用户分组逻辑和实验配置
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
          if (data != null && data.containsKey('app_config')) {
            final configValue = data['app_config'];
            if (configValue != null) {
              int groupValue;
              if (configValue is int) {
                groupValue = configValue;
              } else if (configValue is double) {
                groupValue = configValue.toInt();
              } else {
                groupValue = int.tryParse(configValue.toString()) ?? 1;
              }
              return ExperimentGroup.fromValue(groupValue);
            }
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
      
      if (userDoc.exists) {
        final data = userDoc.data()! as Map<String, dynamic>?;
        if (data != null && data.containsKey('app_config')) {
          final configValue = data['app_config'];
          if (configValue != null) {
            int groupValue;
            if (configValue is int) {
              groupValue = configValue;
            } else if (configValue is double) {
              groupValue = configValue.toInt();
            } else {
              groupValue = int.tryParse(configValue.toString()) ?? 1;
            }
            final group = ExperimentGroup.fromValue(groupValue);
            
            // 检查组别是否发生变化（不更新last_group，避免无限循环）
            await _checkGroupChangeWithoutUpdate(uid, group, data);
            
            return group;
          }
        }
      }

      // 用户还没有分组，进行自动分配
      return await _assignUserGroup(uid);
      
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 获取用户组别失败: $e');
      }
      // 出错时返回默认组别
      return ExperimentGroup.fromValue(
        RemoteConfigService.instance.getDefaultGroup()
      );
    } finally {
      _processingUsers.remove(uid);
    }
  }

  /// 检查组别是否发生变化并处理通知取消
  Future<void> _checkGroupChange(String uid, ExperimentGroup currentGroup, Map<String, dynamic> userData) async {
    try {
      final lastGroupValue = userData['last_group'] as int?;
      
      if (lastGroupValue != null) {
        final lastGroup = ExperimentGroup.fromValue(lastGroupValue);
        
        if (lastGroup != currentGroup) {
          if (kDebugMode) {
            print('ExperimentConfigService: 检测到组别变化: ${lastGroup.name} -> ${currentGroup.name}');
          }
          
          // 取消原组别的所有通知
          final notificationService = _getNotificationService();
          await notificationService.cancelAllUserNotifications(uid);
          
          // 更新last_group字段
          await _firestore.collection('users').doc(uid).update({
            'last_group': currentGroup.value,
            'group_changed_at': FieldValue.serverTimestamp(),
          });
          
          if (kDebugMode) {
            print('ExperimentConfigService: 已取消原组别通知并更新last_group');
          }
        }
      } else {
        // 首次设置last_group字段
        await _firestore.collection('users').doc(uid).update({
          'last_group': currentGroup.value,
        });
        
        if (kDebugMode) {
          print('ExperimentConfigService: 首次设置last_group字段: ${currentGroup.name}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 检查组别变化时出错: $e');
      }
    }
  }

  /// 检查组别是否发生变化并处理通知取消（不更新last_group，避免无限循环）
  Future<void> _checkGroupChangeWithoutUpdate(String uid, ExperimentGroup currentGroup, Map<String, dynamic> userData) async {
    try {
      final lastGroupValue = userData['last_group'] as int?;
      
      if (lastGroupValue != null) {
        final lastGroup = ExperimentGroup.fromValue(lastGroupValue);
        
        if (lastGroup != currentGroup) {
          if (kDebugMode) {
            print('ExperimentConfigService: 检测到组别变化: ${lastGroup.name} -> ${currentGroup.name}');
          }
          
          // 取消原组别的所有通知
          final notificationService = _getNotificationService();
          await notificationService.cancelAllUserNotifications(uid);
          
          // 直接更新last_group字段，不触发新的检测
          await _firestore.collection('users').doc(uid).update({
            'last_group': currentGroup.value,
            'group_changed_at': FieldValue.serverTimestamp(),
          });
          
          // 重新安排新组别的通知
          await _rescheduleNotificationsForNewGroup(uid);
          
          if (kDebugMode) {
            print('ExperimentConfigService: 已取消原组别通知，更新last_group，并重新安排新组别通知');
          }
        }
      } else {
        // 首次设置last_group字段
        await _firestore.collection('users').doc(uid).update({
          'last_group': currentGroup.value,
        });
        
        if (kDebugMode) {
          print('ExperimentConfigService: 首次设置last_group字段: ${currentGroup.name}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 检查组别变化时出错: $e');
      }
    }
  }

  /// 为用户分配实验组
  Future<ExperimentGroup> _assignUserGroup(String uid) async {
    try {
      // 确保 Remote Config 已初始化
      await RemoteConfigService.instance.initialize();
      
      // 检查是否启用实验功能
      if (!RemoteConfigService.instance.isExperimentEnabled()) {
        // 如果实验功能被禁用，所有用户都分配到实验组（保持原有功能）
        final group = ExperimentGroup.experiment;
        await _saveUserGroup(uid, group);
        return group;
      }

      // 获取实验组分配比例
      final experimentRatio = RemoteConfigService.instance.getExperimentGroupRatio();
      
      // 基于 UID 和随机数进行分配，确保分配结果稳定
      final seed = uid.hashCode;
      final deterministicRandom = Random(seed);
      final randomValue = deterministicRandom.nextDouble();
      
      final group = randomValue < experimentRatio 
          ? ExperimentGroup.experiment 
          : ExperimentGroup.control;



      // 保存分组结果
      await _saveUserGroup(uid, group);
      
      if (kDebugMode) {
        print('ExperimentConfigService: 用户 $uid 被分配到: ${group.name} (随机值: $randomValue, 阈值: $experimentRatio)');
      }
      
      return group;
      
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 分配用户组别失败: $e');
      }
      
      // 出错时使用默认组别
      final defaultGroup = ExperimentGroup.fromValue(
        RemoteConfigService.instance.getDefaultGroup()
      );
      
      try {
        await _saveUserGroup(uid, defaultGroup);
      } catch (saveError) {
        if (kDebugMode) {
          print('ExperimentConfigService: 保存默认组别也失败: $saveError');
        }
      }
      
      return defaultGroup;
    }
  }

  /// 保存用户分组到 Firestore
  Future<void> _saveUserGroup(String uid, ExperimentGroup group) async {
    final batch = _firestore.batch();
    
    // 更新用户文档
    final userDoc = _firestore.collection('users').doc(uid);
    batch.set(userDoc, {
      'app_config': group.value,
      'last_group': group.value, // 同时更新last_group字段
      'experiment_assigned_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // 创建分组数据结构
    final groupDoc = userDoc.collection(group.name).doc('data');
    batch.set(groupDoc, {
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // 创建必要的子集合文档
    final eventsDoc = groupDoc.collection('events').doc('_config');
    batch.set(eventsDoc, {
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    final dailyMetricsDoc = groupDoc.collection('daily_metrics').doc('_config');
    batch.set(dailyMetricsDoc, {
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    final appSessionsDoc = groupDoc.collection('app_sessions').doc('_config');
    batch.set(appSessionsDoc, {
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // 提交所有更改
    await batch.commit();
    
    if (kDebugMode) {
      print('ExperimentConfigService: 用户 $uid 分组已保存: ${group.name}');
    }
  }

  /// 重新安排新组别的通知
  Future<void> _rescheduleNotificationsForNewGroup(String uid) async {
    try {
      if (kDebugMode) {
        print('ExperimentConfigService: 开始重新安排新组别的通知...');
      }

      // 获取用户今天的所有活跃事件
      final now = DateTime.now();
      final localToday = DateTime(now.year, now.month, now.day);
      final localTomorrow = localToday.add(const Duration(days: 1));
      final start = localToday.toUtc();
      final end = localTomorrow.toUtc();

      // 获取用户的事件集合
      final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
      
      final snap = await eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .get();

      final allEvents = snap.docs.map(EventModel.fromDoc).toList();
      final activeEvents = allEvents.where((event) => event.isActive).toList();
      
      // 过滤出未开始的事件
      final futureEvents = activeEvents.where((event) => 
        event.scheduledStartTime.isAfter(now) && !event.isDone
      ).toList();

      if (futureEvents.isNotEmpty) {
        // 重新安排通知
        await NotificationScheduler().sync(futureEvents);
        
        if (kDebugMode) {
          print('ExperimentConfigService: 重新安排了 ${futureEvents.length} 个事件的通知');
        }
      } else {
        if (kDebugMode) {
          print('ExperimentConfigService: 没有需要重新安排通知的未来事件');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 重新安排通知失败: $e');
      }
    }
  }

  /// 手动更新last_group字段（用于修复无限循环问题）
  Future<void> _updateLastGroup(String uid, ExperimentGroup group) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'last_group': group.value,
        'group_changed_at': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) {
        print('ExperimentConfigService: 已更新last_group字段: ${group.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 更新last_group失败: $e');
      }
    }
  }

  /// 手动设置用户组别（用于测试或管理员功能）
  Future<void> setUserGroup(String uid, ExperimentGroup group) async {
    try {
      await _saveUserGroup(uid, group);
      if (kDebugMode) {
        print('ExperimentConfigService: 手动设置用户 $uid 为: ${group.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 手动设置用户组别失败: $e');
      }
      rethrow;
    }
  }

  /// 获取NotificationService实例
  NotificationService _getNotificationService() {
    return NotificationService.instance;
  }

  /// 检查用户是否为实验组
  Future<bool> isExperimentGroup(String uid) async {
    final group = await getUserGroup(uid);
    return group == ExperimentGroup.experiment;
  }

  /// 检查用户是否为对照组
  Future<bool> isControlGroup(String uid) async {
    final group = await getUserGroup(uid);
    return group == ExperimentGroup.control;
  }

  /// 获取实验配置统计信息（用于调试）
  Future<Map<String, dynamic>> getExperimentStats() async {
    try {
      final usersQuery = await _firestore
          .collection('users')
          .where('app_config', whereIn: [0, 1])
          .get();

      int controlCount = 0;
      int experimentCount = 0;
      
      for (final doc in usersQuery.docs) {
        final appConfig = doc.data()['app_config'] as int;
        if (appConfig == 0) {
          controlCount++;
        } else {
          experimentCount++;
        }
      }

      return {
        'total_users': controlCount + experimentCount,
        'control_count': controlCount,
        'experiment_count': experimentCount,
        'control_ratio': controlCount / (controlCount + experimentCount),
        'experiment_ratio': experimentCount / (controlCount + experimentCount),
        'remote_config': RemoteConfigService.instance.getConfigInfo(),
      };
    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 获取统计信息失败: $e');
      }
      return {'error': e.toString()};
    }
  }

  /// 迁移现有用户到实验组（一次性迁移脚本）
  Future<void> migrateExistingUsersToExperiment() async {
    try {
      if (kDebugMode) {
        print('ExperimentConfigService: 开始迁移现有用户...');
      }

      final usersQuery = await _firestore
          .collection('users')
          .where('app_config', isNull: true)
          .get();

      final batch = _firestore.batch();
      int migratedCount = 0;

      for (final doc in usersQuery.docs) {
        batch.set(doc.reference, {
          'app_config': ExperimentGroup.experiment.value,
          'experiment_assigned_at': FieldValue.serverTimestamp(),
          'migrated_from_existing': true,
        }, SetOptions(merge: true));
        
        migratedCount++;
      }

      if (migratedCount > 0) {
        await batch.commit();
        if (kDebugMode) {
          print('ExperimentConfigService: 成功迁移 $migratedCount 个现有用户到实验组');
        }
      } else {
        if (kDebugMode) {
          print('ExperimentConfigService: 没有需要迁移的用户');
        }
      }

    } catch (e) {
      if (kDebugMode) {
        print('ExperimentConfigService: 迁移现有用户失败: $e');
      }
      rethrow;
    }
  }

  /// 测试组别切换功能（用于调试）
  Future<void> testGroupSwitch(String uid) async {
    try {
      final currentGroup = await getUserGroup(uid);
      final newGroup = currentGroup == ExperimentGroup.control 
          ? ExperimentGroup.experiment 
          : ExperimentGroup.control;
      
      if (kDebugMode) {
        print('测试组别切换: 从 ${currentGroup.name} 切换到 ${newGroup.name}');
      }
      
      await setUserGroup(uid, newGroup);
      
      if (kDebugMode) {
        print('测试组别切换完成');
      }
    } catch (e) {
      if (kDebugMode) {
        print('测试组别切换失败: $e');
      }
      rethrow;
    }
  }

  /// 手动触发组别检查（用于调试）
  Future<void> triggerGroupCheck(String uid) async {
    try {
      if (kDebugMode) {
        print('手动触发组别检查...');
      }
      
      await getUserGroup(uid);
      
      if (kDebugMode) {
        print('组别检查完成');
      }
    } catch (e) {
      if (kDebugMode) {
        print('组别检查失败: $e');
      }
      rethrow;
    }
  }

  /// 修复无限循环问题（手动同步last_group和app_config）
  Future<void> fixInfiniteLoop(String uid) async {
    try {
      if (kDebugMode) {
        print('开始修复无限循环问题...');
      }
      
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()! as Map<String, dynamic>?;
        if (data != null) {
          final appConfig = data['app_config'] as int?;
          final lastGroup = data['last_group'] as int?;
          
          if (appConfig != null) {
            final currentGroup = ExperimentGroup.fromValue(appConfig);
            
            // 强制同步last_group和app_config
            await _firestore.collection('users').doc(uid).update({
              'last_group': appConfig,
              'group_changed_at': FieldValue.serverTimestamp(),
            });
            
            if (kDebugMode) {
              print('已修复: app_config=$appConfig, last_group=$lastGroup -> last_group=$appConfig');
            }
          }
        }
      }
      
      if (kDebugMode) {
        print('无限循环问题修复完成');
      }
    } catch (e) {
      if (kDebugMode) {
        print('修复无限循环问题失败: $e');
      }
      rethrow;
    }
  }
} 