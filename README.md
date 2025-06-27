# Momentum Flutter App

一個基於 Flutter 的任務管理應用，整合 Google Calendar 和智能通知系統。

## 功能特色

### 雙重通知系統
應用實現了智能的雙重通知機制來提高任務完成率：

1. **第一個通知**：任務開始前 10 分鐘
   - 提醒用戶任務即將開始
   - 內容：「您的任務「[任務名稱]」即將開始」

2. **第二個通知**：任務開始後 5 分鐘
   - 檢查任務是否已開始，如果未開始則發送提醒
   - 內容：「您的任務「[任務名稱]」應該已經開始了，請檢查並開始執行！」
   - 當用戶開始任務時，第二個通知會自動取消

### 通知管理
- **自動排程**：創建任務時自動排程兩個通知
- **智能取消**：任務開始或完成時自動取消所有通知
- **狀態同步**：與 Firestore 數據庫同步通知狀態
- **衝突避免**：使用正負數 ID 避免通知 ID 衝突

### 技術實現
- 使用 `flutter_local_notifications` 實現本地通知
- 支持 iOS 和 Android 平台
- 時區感知的準確時間計算
- 背景狀態下的可靠通知觸發

## 開發指南

### 測試通知功能
```dart
// 測試單個通知
await NotificationService.instance.showTestNotification();

// 測試雙重通知
await NotificationService.instance.showTestDualNotification();
```

### 手動同步通知
```dart
// 同步指定事件列表的通知
await NotificationScheduler().sync(events);

// 取消特定事件的通知
await NotificationScheduler().cancelEventNotification(eventId, notifId, secondNotifId);
```

## 數據模型

### EventModel 新增字段
```dart
final int? secondNotifId;           // 第二個通知的 ID
final DateTime? secondNotifScheduledAt;  // 第二個通知的排程時間
```

## 配置

### 通知時間設置
```dart
const int firstNotifOffsetMin = -10;   // 第一個通知：開始前10分鐘
const int secondNotifOffsetMin = 5;    // 第二個通知：開始後5分鐘
```

這些時間可以根據需求調整。

## 注意事項

1. **權限要求**：iOS 需要通知權限才能正常工作
2. **時區處理**：通知會根據設備時區自動調整
3. **背景執行**：通知在 app 背景或關閉時仍能正常觸發
4. **數據同步**：通知狀態會與 Firestore 同步，確保數據一致性

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
