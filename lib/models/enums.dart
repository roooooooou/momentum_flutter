/// 任務開始觸發方式
enum StartTrigger {
  tapNotification(0),  // 點擊通知
  tapCard(1),         // 點擊卡片
  chat(2);          // 自動開始

  const StartTrigger(this.value);
  final int value;

  static StartTrigger fromValue(int value) {
    return StartTrigger.values.firstWhere((e) => e.value == value);
  }
}

/// 任務狀態
enum TaskStatus {
  notStarted(0),   // 未開始
  inProgress(1),   // 進行中
  completed(2),    // 已完成
  overdue(3);      // 逾期

  const TaskStatus(this.value);
  final int value;

  static TaskStatus fromValue(int value) {
    return TaskStatus.values.firstWhere((e) => e.value == value);
  }
}

/// 通知結果
enum NotificationResult {
  dismiss(0),   // 忽略/關閉
  snooze(1),    // 延後
  start(2);     // 開始

  const NotificationResult(this.value);
  final int value;

  static NotificationResult fromValue(int value) {
    return NotificationResult.values.firstWhere((e) => e.value == value);
  }
} 