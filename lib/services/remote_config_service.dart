import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

/// Firebase Remote Config 服务
/// 用于管理实验组配置和其他远程配置参数
class RemoteConfigService {
  RemoteConfigService._();
  static final instance = RemoteConfigService._();

  FirebaseRemoteConfig? _remoteConfig;
  bool _initialized = false;

  /// 初始化 Remote Config
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _remoteConfig = FirebaseRemoteConfig.instance;
      
      // 设置配置参数默认值
      await _remoteConfig!.setDefaults(const {
        'experiment_group_ratio': 0.5, // legacy
        'default_group': 1.0, // legacy
        'enable_experiment': true, // 是否启用实验功能
        // 新：以週為單位分派的預設與覆寫
        // 'A' = 週1=experiment, 週2=control；'B' = 週1=control, 週2=experiment
        'default_week_assignment': 'A',
        // JSON: { "uid1": "A", "uid2": "B" }
        'week_assignment_overrides_json': '{}',
      });

      // 设置获取配置的设置
      await _remoteConfig!.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: Duration(
            // 在调试模式下使用较短的间隔，生产环境使用较长间隔
            hours: kDebugMode ? 1 : 12,
          ),
        ),
      );

      // 获取远程配置
      await _remoteConfig!.fetchAndActivate();
      
      _initialized = true;
      
      if (kDebugMode) {
        print('RemoteConfigService: 初始化成功');
        print('实验组比例: ${getExperimentGroupRatio()}');
        print('默认组别: ${getDefaultGroup()}');
        print('实验功能启用: ${isExperimentEnabled()}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('RemoteConfigService: 初始化失败: $e');
      }
      _initialized = false;
    }
  }

  /// 获取实验组分配比例 (0.0 - 1.0)
  double getExperimentGroupRatio() {
    if (!_initialized || _remoteConfig == null) {
      return 0.5;
    }
    try {
      final value = _remoteConfig!.getDouble('experiment_group_ratio');
      return value.isNaN ? 0.5 : value;
    } catch (e) {
      if (kDebugMode) {
        print('RemoteConfigService: 获取实验组比例失败，使用默认值: $e');
      }
      return 0.5;
    }
  }

  /// 获取默认组别 (0 = 对照组, 1 = 实验组)
  int getDefaultGroup() {
    if (!_initialized || _remoteConfig == null) {
      return 1;
    }
    try {
      // 先尝试获取double值，然后转换为int
      final value = _remoteConfig!.getDouble('default_group');
      return value.round();
    } catch (e) {
      if (kDebugMode) {
        print('RemoteConfigService: 获取默认组别失败，使用默认值: $e');
      }
      return 1;
    }
  }

  /// 检查是否启用实验功能
  bool isExperimentEnabled() {
    if (!_initialized || _remoteConfig == null) {
      return true;
    }
    try {
      final value = _remoteConfig!.getBool('enable_experiment');
      return value;
    } catch (e) {
      if (kDebugMode) {
        print('RemoteConfigService: 获取实验功能状态失败，使用默认值: $e');
      }
      return true;
    }
  }

  /// 取得指定使用者的週分派規則（A/B），可被 Remote Config 覆寫
  String getWeekAssignmentForUser(String uid) {
    if (!_initialized || _remoteConfig == null) {
      return 'A';
    }
    try {
      final overrides = _remoteConfig!.getString('week_assignment_overrides_json');
      if (overrides.isNotEmpty) {
        final Map<String, dynamic> map = _safeJsonDecode(overrides);
        final v = map[uid];
        if (v is String && (v == 'A' || v == 'B')) {
          return v;
        }
      }
    } catch (_) {}
    try {
      final def = _remoteConfig!.getString('default_week_assignment');
      return (def == 'B') ? 'B' : 'A';
    } catch (_) {
      return 'A';
    }
  }

  Map<String, dynamic> _safeJsonDecode(String s) {
    try {
      return s.isEmpty ? {} : (jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return {};
    }
  }

  /// 强制刷新配置（用于测试）
  Future<void> forceRefresh() async {
    if (!_initialized) return;
    
    try {
      await _remoteConfig!.fetchAndActivate();
      if (kDebugMode) {
        print('RemoteConfigService: 配置已刷新');
      }
    } catch (e) {
      if (kDebugMode) {
        print('RemoteConfigService: 刷新配置失败: $e');
      }
    }
  }

  /// 获取配置状态信息（用于调试）
  Map<String, dynamic> getConfigInfo() {
    if (!_initialized) return {'initialized': false};
    
    return {
      'initialized': _initialized,
      'experiment_group_ratio': getExperimentGroupRatio(),
      'default_group': getDefaultGroup(),
      'enable_experiment': isExperimentEnabled(),
      'last_fetch_time': _remoteConfig!.lastFetchTime.toIso8601String(),
      'last_fetch_status': _remoteConfig!.lastFetchStatus.name,
    };
  }
} 