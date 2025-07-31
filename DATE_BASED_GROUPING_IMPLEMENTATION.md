# 基于日期的分组实现

## 概述

本次修改将用户分组从基于 app config 的静态分配改为基于日期的动态分配。每个用户在未来15天内，每一天都会被随机分配到实验组或对照组。

## 主要改动

### 1. ExperimentConfigService 重构

**文件**: `lib/services/experiment_config_service.dart`

- 移除了基于 Remote Config 的组别分配
- 新增基于日期的组别分配逻辑
- 为每个用户生成未来15天的日期分组配置
- 新增 `getDateGroup()` 方法获取指定日期的组别

**关键方法**:
- `_generateDateGroupings()`: 生成未来15天的随机分组
- `getDateGroup(uid, date)`: 获取指定日期的组别
- `isExperimentGroup(uid)`: 检查当前日期是否为实验组

### 2. DataPathService 更新

**文件**: `lib/services/data_path_service.dart`

- 修改数据存储路径格式为: `users/user_id/experiment/events/event_id` 或 `users/user_id/control/events/event_id`
- 新增基于日期的路径获取方法
- 所有数据访问都基于当前日期或指定日期

**新的路径结构**:
```
users/
  {user_id}/
    experiment/
      events/
          {event_id}
      app_sessions/
        {session_id}
      daily_metrics/
        {date}
    control/
      events/
        {event_id}
      app_sessions/
        {session_id}
      daily_metrics/
        {date}
```

### 3. AuthService 增强

**文件**: `lib/services/auth_service.dart`

- 新用户创建时自动分配日期分组
- 获取未来15天的 Google Calendar 任务
- 按日期将任务分配到对应的实验组或对照组
- 老用户自动迁移到新的日期分组系统

**关键方法**:
- `_initializeNewUser()`: 初始化新用户
- `_fetchAndDistributeFutureTasks()`: 获取并分配未来任务
- `_migrateExistingUser()`: 迁移现有用户

### 4. CalendarService 更新

**文件**: `lib/services/calendar_service.dart`

- 新增 `isInitialized` 属性
- 新增 `getCalendarList()` 和 `getEvents()` 方法
- 所有事件操作都基于当前日期的组别

### 5. EventsProvider 修改

**文件**: `lib/providers/events_provider.dart`

- 事件查询基于当前日期的组别
- 支持跨日时的组别切换

### 6. HomeScreen 更新

**文件**: `lib/screens/home_screen.dart`

- 根据当前日期的组别显示聊天按钮
- App resume 时重新检查当前日期的组别
- 处理跨日时的组别变化

### 7. 其他服务更新

- **ChatProvider**: 聊天数据基于当前日期的组别
- **ExperimentEventHelper**: 实验数据收集基于当前日期的组别
- **ProactCoachService**: 聊天总结基于指定日期的组别

## 数据迁移

### 新用户
1. 创建用户文档
2. 生成未来15天的日期分组配置
3. 获取 Google Calendar 未来15天任务
4. 按日期分配到对应组别

### 老用户
1. 检测是否已有日期分组配置
2. 如果没有，自动生成并保存
3. 保持现有数据不变

## 使用示例

```dart
// 获取当前日期的组别
final group = await ExperimentConfigService.instance.getDateGroup(uid, DateTime.now());

// 检查当前日期是否为实验组
final isExperiment = await ExperimentConfigService.instance.isExperimentGroup(uid);

// 获取指定日期的事件集合
final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, targetDate);
```

## 注意事项

1. **跨日处理**: App resume 时会重新检查当前日期的组别，确保跨日时正确切换
2. **数据一致性**: 所有数据操作都基于当前日期或指定日期的组别
3. **向后兼容**: 老用户会自动迁移到新系统，不会丢失数据
4. **随机性**: 日期分组基于用户 UID 的哈希值，确保同一用户的分组结果稳定

## 测试建议

1. 测试新用户注册时的分组分配
2. 测试老用户的自动迁移
3. 测试跨日时的组别切换
4. 测试不同日期的事件数据访问
5. 测试聊天功能的组别显示 