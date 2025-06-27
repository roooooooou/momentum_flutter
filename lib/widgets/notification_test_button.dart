import 'package:flutter/material.dart';
import '../services/notification_handler.dart';

class NotificationTestButton extends StatelessWidget {
  const NotificationTestButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _testNotification(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      child: const Text('測試通知彈窗'),
    );
  }

  void _testNotification(BuildContext context) async {
    const testEventId = 'test_event_123'; // 測試用的事件ID

    // 模擬通知點擊
    await NotificationHandler.instance.handleNotificationTap(testEventId);

    // 顯示提示訊息
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已觸發測試通知彈窗（注意：測試ID可能找不到實際事件）'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
} 