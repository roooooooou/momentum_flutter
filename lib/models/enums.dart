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

/// 任務狀態
enum TaskStatus {
  notStarted(0),   // 未開始
  inProgress(1),   // 進行中
  completed(2),    // 已完成
  overdue(3),      // 逾期（未開始但過了開始時間）
  overtime(4);     // 超時（已開始但超過預計結束時間）

  const TaskStatus(this.value);
  final int value;

  static TaskStatus fromValue(int value) {
    return TaskStatus.values.firstWhere((e) => e.value == value);
  }
}

/// 事件生命周期状态
enum EventLifecycleStatus {
  active(0),      // 活跃（正常存在于Google Calendar中）
  deleted(1),     // 已从Google Calendar中删除
  moved(2);       // 在同一日历内移动（时间改变）

  const EventLifecycleStatus(this.value);
  final int value;

  static EventLifecycleStatus fromValue(int value) {
    return EventLifecycleStatus.values.firstWhere((e) => e.value == value);
  }

  String get displayName {
    switch (this) {
      case EventLifecycleStatus.active:
        return '活躍';
      case EventLifecycleStatus.deleted:
        return '已刪除';
      case EventLifecycleStatus.moved:
        return '已移動';
    }
  }
}

/// 通知结果
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

/// 聊天結果
enum ChatResult {
  start(0),    // 開始任務
  snooze(1),   // 延後
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