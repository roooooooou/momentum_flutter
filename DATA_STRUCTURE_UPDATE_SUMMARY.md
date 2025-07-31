# 數據結構修改完成總結

## 概述

已成功將數據結構從基於組別的嵌套結構修改為按日期分組的扁平結構，並解決了相關的權限問題。

## 完成的修改

### 1. 新的數據結構

**舊結構**:
```
users/
  {user_id}/
    experiment/
      events/
        {event_id}
    control/
      events/
        {event_id}
```

**新結構**:
```
users/
  {user_id}/
    experiment_events/
      {event_id}  // 文檔包含 date 字段
    control_events/
      {event_id}  // 文檔包含 date 字段
    sessions/
      {session_id} 
    daily_metrics/
      {date}  // 文檔包含 group 字段
```

### 2. 修改的文件

#### 核心模型
- **`lib/models/event_model.dart`**: 添加 `date` 字段，更新所有相關方法
- **`lib/models/daily_report_model.dart`**: 添加 `group` 字段，更新所有相關方法

#### 服務文件
- **`lib/services/data_path_service.dart`**: 新增支持新結構的方法
- **`lib/services/auth_service.dart`**: 更新以支持新結構
- **`lib/services/app_usage_service.dart`**: 修復方法調用錯誤
- **`lib/services/calendar_service.dart`**: 簡化數據結構初始化

#### 界面文件
- **`lib/screens/daily_report_screen.dart`**: 修復構造函數調用

#### 配置文件
- **`firestore.rules`**: 更新以支持新的數據結構

### 3. 解決的問題

#### Firestore 權限錯誤
- **問題**: `[cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation.`
- **原因**: Firestore 規則還是基於舊的數據結構
- **解決**: 更新 `firestore.rules` 以支持新的數據結構，並成功部署

#### 編譯錯誤
- 修復了所有編譯錯誤
- 移除了對已刪除服務的引用
- 更新了方法調用以匹配新的數據結構

### 4. 新的 Firestore 規則

```javascript
// 實驗組事件數據
match /users/{userId}/experiment_events/{eventId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}

// 對照組事件數據
match /users/{userId}/control_events/{eventId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}

// 會話數據
match /users/{userId}/sessions/{sessionId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}

// 每日指標數據
match /users/{userId}/daily_metrics/{dateId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

### 5. 使用示例

#### 獲取事件集合
```dart
// 獲取實驗組事件集合
final experimentEvents = await DataPathService.instance.getUserExperimentEventsCollection(uid);

// 獲取對照組事件集合
final controlEvents = await DataPathService.instance.getUserControlEventsCollection(uid);

// 根據組別獲取事件集合
final eventsCollection = await DataPathService.instance.getEventsCollectionByGroup(uid, 'experiment');
```

#### 創建事件
```dart
final event = EventModel(
  id: 'event_123',
  title: '測試任務',
  scheduledStartTime: DateTime.now(),
  scheduledEndTime: DateTime.now().add(Duration(hours: 1)),
  isDone: false,
  date: DateTime.now(), // 新增必需字段
);
```

## 編譯狀態

✅ **所有編譯錯誤已修復**
- 修復了 Firestore 權限問題
- 更新了所有相關的方法調用
- 移除了對已刪除服務的引用

⚠️ **剩餘的警告和信息**
- 主要是代碼風格建議（如使用 `const`、避免 `print` 等）
- 一些未使用的變量警告
- 這些不會影響編譯和運行

## 優勢

1. **更靈活的查詢**: 可以輕鬆按日期範圍查詢事件
2. **更好的性能**: 扁平結構減少嵌套查詢
3. **更清晰的組織**: 實驗組和對照組數據分離
4. **向後兼容**: 保留了舊數據結構的規則以支持逐步遷移

## 下一步

1. 測試新數據結構的功能
2. 監控應用程序的運行情況
3. 根據實際使用情況進行進一步優化 