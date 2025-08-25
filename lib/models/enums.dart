/// 任務開始觸發方式
enum StartTrigger {
  tapNotification(0),  // 點擊通知
  tapCard(1),         // 點擊卡片
  chat(2),            // 聊天開始
  dailyReport(3);     // 每日報告完成

  const StartTrigger(this.value);
  final int value;

  static StartTrigger fromValue(int value) {
    return StartTrigger.values.firstWhere((e) => e.value == value);
  }
}

/// Task Start Dialog 觸發來源
enum TaskStartDialogTrigger {
  notification(0),  // 來自通知點擊
  appResume(1),    // 來自 app resume
  manual(2);       // 手動觸發

  const TaskStartDialogTrigger(this.value);
  final int value;

  static TaskStartDialogTrigger fromValue(int value) {
    return TaskStartDialogTrigger.values.firstWhere((e) => e.value == value);
  }
}

/// 任務狀態
enum TaskStatus {
  notStarted(0),   // 未開始
  inProgress(1),   // 進行中
  completed(2),    // 已完成
  overdue(3),      // 逾期（未開始但過了開始時間）
  overtime(4),     // 超時（已開始但超過預計結束時間）
  paused(5);       // 暫停（已開始但暫時停止）

  const TaskStatus(this.value);
  final int value;

  static TaskStatus fromValue(int value) {
    return TaskStatus.values.firstWhere((e) => e.value == value);
  }
}



/// 通知结果
enum NotificationResult {
  dismiss(0),   // 忽略/關閉
  snooze(1),  // 對照組：延後
  chat(2),    // 實驗組：聊天
  start(3),    // 開始
  cancel(4); // 任務已開始，通知取消

  const NotificationResult(this.value);
  final int value;

  static NotificationResult fromValue(int value) {
    return NotificationResult.values.firstWhere((e) => e.value == value);
  }
}

/// 聊天結果
enum ChatResult {
  start(0),    // 開始任務
  snooze(1),   // 放棄
  leave(2);    // 直接離開

  const ChatResult(this.value);
  final int value;

  static ChatResult fromValue(int value) {
    return ChatResult.values.firstWhere((e) => e.value == value);
  }
}

/// 聊天進入方式
enum ChatEntryMethod {
  notification(0),  // 通過通知進入
  eventCard(1);     // 通過事件卡片進入

  const ChatEntryMethod(this.value);
  final int value;

  static ChatEntryMethod fromValue(int value) {
    return ChatEntryMethod.values.firstWhere((e) => e.value == value);
  }
} 