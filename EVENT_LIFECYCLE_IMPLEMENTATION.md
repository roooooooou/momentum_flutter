# 事件生命周期管理功能实现

## 概述

本功能实现了在Google Calendar事件被删除或移动时，在Firebase中保留完整的事件记录和历史。这样可以追踪事件的完整生命周期，支持实验数据分析。

## 核心功能

### 1. 事件状态追踪

**新增枚举类型 `EventLifecycleStatus`：**
- `active` (0) - 活跃（正常存在于Google Calendar中）
- `deleted` (1) - 已从Google Calendar中删除
- `moved` (2) - 在同一日历内移动（时间改变）

### 2. 数据模型扩展

**EventModel新增字段：**
```dart
// 事件生命周期相关字段
final EventLifecycleStatus? lifecycleStatus;  // 事件生命周期状态
final DateTime? archivedAt;                    // 归档时间
final String? previousEventId;                 // 关联的移动记录ID
final DateTime? movedFromStartTime;            // 移动前的开始时间
final DateTime? movedFromEndTime;              // 移动前的结束时间

// 便利方法
bool get isActive;    // 是否为活跃事件
bool get isArchived;  // 是否为已归档事件
```

### 3. 同步逻辑改进

**不再直接删除事件，而是：**

#### 删除检测
当Google Calendar中不存在某个事件时：
1. 将事件标记为 `deleted` 状态
2. 设置 `archivedAt` 时间戳
3. 取消相关通知
4. 保留所有历史数据

#### 移动检测与处理（重要改进）
当事件时间发生变化时，采用新的处理方式：

1. **保存历史记录**：
   - 将原事件文档重命名为 `原ID_moved_时间戳`
   - 标记为 `moved` 状态并保存历史数据

2. **创建新状态**：
   - 删除原文档
   - 重新创建原ID文档，保存Google Calendar的新数据
   - 设置 `previousEventId` 关联到历史记录

```dart
// 移动处理示例
final originalEventId = localDoc.id;  // 例如: "abc123xyz"
final movedEventId = '${originalEventId}_moved_${now.millisecondsSinceEpoch}';

// 1) 将原事件重命名为移动记录 (ID: "abc123xyz_moved_1674123456789")
final movedData = Map<String, dynamic>.from(localData);
movedData.addAll({
  'lifecycleStatus': EventLifecycleStatus.moved.value,
  'archivedAt': Timestamp.fromDate(now),
  'movedFromStartTime': originalStart,
  'movedFromEndTime': originalEnd,
});
batch.set(movedRef, movedData);

// 2) 删除原文档
batch.delete(localDoc.reference);

// 3) 重新创建原ID文档 (ID: "abc123xyz")
final newData = {
  // ... Google Calendar的新数据
  'previousEventId': movedEventId, // 关联到历史记录
  'lifecycleStatus': EventLifecycleStatus.active.value,
};
batch.set(originalRef, newData);
```

**优势：**
- Google Calendar ID始终对应最新状态
- 完整保留移动历史
- 支持多次移动的历史链追踪

### 4. UI显示优化

**EventsProvider只显示活跃事件：**
```dart
_stream = FirebaseFirestore.instance
    .collection('users')
    .doc(user.uid)
    .collection('events')
    .where('scheduledStartTime', isGreaterThanOrEqualTo: startTs)
    .where('scheduledStartTime', isLessThan: endTs)
    .orderBy('scheduledStartTime')
    .snapshots()
    .map((q) => q.docs
        .map(EventModel.fromDoc)
        .where((event) => event.isActive) // 只显示活跃事件
        .toList());
```

## 使用方法

### 1. 查询已归档事件

```dart
// 获取最近删除的事件
final deletedEvents = await ExperimentEventHelper.getArchivedEvents(
  uid: userId,
  status: EventLifecycleStatus.deleted,
  limit: 20,
);

// 获取移动的事件记录
final movedEvents = await ExperimentEventHelper.getArchivedEvents(
  uid: userId,
  status: EventLifecycleStatus.moved,
  limit: 20,
);
```

### 2. 查看事件历史

```dart
// 获取事件的完整移动历史
final history = await ExperimentEventHelper.getEventHistory(
  uid: userId,
  eventId: eventId,
);
```

### 3. 统计生命周期状态

```dart
// 获取各状态事件数量统计
final stats = await ExperimentEventHelper.getLifecycleStats(
  uid: userId,
  startDate: DateTime.now().subtract(Duration(days: 30)),
  endDate: DateTime.now(),
);
```

### 4. 调试界面

使用 `EventLifecycleDebugWidget` 来查看事件生命周期状态：

```dart
// 在调试页面中显示
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => EventLifecycleDebugWidget(
      user: FirebaseAuth.instance.currentUser!,
    ),
  ),
);
```

## 实现细节

### 时间变化检测

```dart
bool _hasTimeChanged(DateTime localStart, DateTime localEnd, 
                    DateTime apiStart, DateTime apiEnd) {
  // 允许30秒误差（处理时区和精度问题）
  const tolerance = Duration(seconds: 30);
  
  return (localStart.difference(apiStart).abs() > tolerance) ||
         (localEnd.difference(apiEnd).abs() > tolerance);
}
```

### 移动处理的ID策略

**原设计问题：** Google Calendar移动事件后，event ID保持不变，直接创建新ID会丢失原有关联。

**新设计方案：**
- 移动记录使用：`原ID_moved_时间戳`
- 原文档保持原ID，更新内容
- 通过 `previousEventId` 建立关联链

**示例：**
```
原事件: abc123xyz (08:00-09:00)
移动到: abc123xyz (10:00-11:00)

结果:
- abc123xyz: 新时间 10:00-11:00, previousEventId: "abc123xyz_moved_1674123456"
- abc123xyz_moved_1674123456: 原时间 08:00-09:00, status: moved
```

### 批量操作优化

所有的归档和创建操作都使用Firestore批量写入，确保原子性和性能。

### 通知管理

当事件被删除或移动时，会自动取消相关的通知排程，避免无效通知。

## 数据保留策略

1. **删除事件**: 完整保留原始数据，只改变状态标识
2. **移动事件**: 
   - 创建移动记录保存历史状态
   - 原文档更新为新状态
   - 通过previousEventId链接历史
3. **实验数据**: 移动时会复制重要的实验字段到新状态
4. **历史追踪**: 支持多次移动的完整历史链

## 兼容性

- 现有事件会被自动标记为 `active` 状态
- 向后兼容，不影响现有功能
- 新功能对UI透明，用户体验无变化
- Google Calendar ID始终对应最新状态

## 测试建议

1. 在Google Calendar中删除事件，验证Firebase中事件被标记为deleted
2. 移动事件时间，验证原事件重命名为历史记录，新事件使用原ID
3. 多次移动同一事件，验证历史链的完整性
4. 验证移动后原ID仍对应最新的事件状态
5. 使用调试界面查看各种状态的事件统计
