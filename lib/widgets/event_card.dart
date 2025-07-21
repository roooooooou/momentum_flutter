import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import 'dart:async';

enum TaskAction { start, stop, complete, continue_ }

class EventCard extends StatefulWidget {
  const EventCard(
      {super.key,
      required this.event,
      required this.onAction,
      required this.onOpenChat});

  final EventModel event;
  final void Function(TaskAction a) onAction;
  final void Function() onOpenChat;

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    // 只有当任务进行中或超时时才启动计时器（暂停状态不启动计时器）
    if (widget.event.computedStatus == TaskStatus.inProgress || 
        widget.event.computedStatus == TaskStatus.overtime) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            // 强制重建widget以更新时间显示
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(EventCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果任务状态改变，重新处理计时器
    if (oldWidget.event.computedStatus != widget.event.computedStatus) {
      _timer?.cancel();
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get responsive sizing information
    final size = MediaQuery.of(context).size;
    final responsiveText = MediaQuery.textScalerOf(context).scale(1.0);

    // Responsive sizes
    final cardBorderRadius = size.width * 0.03; // 6% of screen width
    final cardHPadding = size.width * 0.045; // 4.5% of screen width
    final cardVPadding = size.height * 0.022; // 2.2% of screen height
    final iconSize = size.width * 0.7 > 43 ? 43.0 : size.width * 0.7; // 放大圓圈
    final titleFontSize = (19 * responsiveText).clamp(16.0, 23.0);
    final subtitleFontSize = (15 * responsiveText).clamp(14.0, 19.0);

    // --- Card background color based on status ---------------------------
    late final Color bg;
    late final Color statusColor;
    late final Color circleColor;

    switch (widget.event.computedStatus) {
      case TaskStatus.inProgress:
        bg = const Color(0xFFEFEBE2); // Light grey-green
        statusColor = const Color(0xFF8D9B97); // Grey-green for in-progress
        circleColor = const Color(0xFF99A59D); // Light green for in-progress
        break;
      case TaskStatus.overdue:
        bg = const Color(0xFFF2E9E0); // Light pinkish
        statusColor = const Color(0xFFE5A79D); // Salmon color for overdue
        circleColor = const Color(0xFFC7917C); // Light grey for overdue
        break;
      case TaskStatus.overtime:
        bg = const Color(0xFFF5E6E6); // Light red-ish
        statusColor = const Color(0xFFD4756B); // Red-ish color for overtime
        circleColor = const Color(0xFFB85450); // Darker red for overtime
        break;
      case TaskStatus.completed:
        bg = const Color(0xFFCBD0C9); // Desaturated blue-grey
        statusColor = const Color(0XFF6F7C71);
        circleColor = const Color(0xFF99A59D);
        break;
      case TaskStatus.paused:
        bg = const Color(0xFFF0E8F5); // Light purple-ish for paused
        statusColor = const Color(0xFF9B8AA0); // Purple-grey for paused
        circleColor = const Color(0xFF8A7CA8); // Darker purple for paused
        break;
      case TaskStatus.notStarted:
      default:
        bg = const Color(0xFFEFEBE2); // Light grey
        statusColor = const Color(0xFF8D9B97); // Grey-green
        circleColor = const Color(0xFF99A59D);
    }

    return LayoutBuilder(builder: (context, constraints) {
      // Calculate spacing based on available width
      final horizontalSpacing = constraints.maxWidth * 0.03;

      return Opacity(
        opacity: widget.event.computedStatus == TaskStatus.completed ? 0.85 : 1,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: cardHPadding,
            vertical: cardVPadding,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(cardBorderRadius),
            // 增強卡片陰影效果
            boxShadow: const [
              BoxShadow(
                blurRadius: 8,
                offset: Offset(0, 4),
                spreadRadius: -2,
                color: Color(0x50000000),
              ),
              BoxShadow(
                blurRadius: 1,
                offset: Offset(0, 2),
                spreadRadius: 0,
                color: Color(0x30000000),
              )
            ],
          ),
          child: Row(
            children: [
              _StatusIcon(
                status: widget.event.computedStatus,
                color: circleColor,
                size: iconSize,
                // 移除完成功能
              ),
              SizedBox(width: horizontalSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.event.title,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: size.height * 0.005),
                    Text(
                      _subtitleText(widget.event),
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: statusColor, // Grey for other text
                      ),
                    ),
                  ],
                ),
              ),
              _ActionButton(
                status: widget.event.computedStatus,
                onStart: () => widget.onAction(TaskAction.start),
                onStop: () => widget.onAction(TaskAction.stop),
                onComplete: () => widget.onAction(TaskAction.complete), // 新增完成功能
                onContinue: () => widget.onAction(TaskAction.continue_), // 新增繼續功能
                onChat: () => widget.onOpenChat(),
                // Pass in responsive size parameters
                buttonHeight: size.height * 0.045,
                buttonWidth: size.width * 0.2,
                borderRadius: size.width * 0.02,
                fontSize: subtitleFontSize,
              ),
            ],
          ),
        ),
      );
    });
  }

  static String _subtitleText(EventModel e) {
    return switch (e.computedStatus) {
      TaskStatus.inProgress => _getCountdownText(e),
      TaskStatus.overtime => _getCountdownText(e), // 超時也顯示倒數時間（會顯示超時多久）
      TaskStatus.overdue => 'Overdue',
      TaskStatus.notStarted => e.timeRange,
      TaskStatus.completed => 'Complete',
      TaskStatus.paused => '已暫停 - ${_getPausedTimeText(e)}', // 暫停狀態顯示暫停信息
    };
  }

  /// 计算并返回倒数时间文本
  static String _getCountdownText(EventModel event) {
    final now = DateTime.now();
    
    // 计算动态结束时间
    DateTime targetEndTime;
    if (event.actualStartTime != null) {
      // 如果有实际开始时间，使用实际开始时间 + 任务时长
      final taskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
      targetEndTime = event.actualStartTime!.add(taskDuration);
    } else {
      // 如果没有实际开始时间，使用原定结束时间
      targetEndTime = event.scheduledEndTime;
    }
    
    final difference = targetEndTime.difference(now);
    
    if (difference.isNegative) {
      // 如果已经超过结束时间，显示超时
      final overdue = now.difference(targetEndTime);
      final hours = overdue.inHours;
      final minutes = overdue.inMinutes.remainder(60);
      final seconds = overdue.inSeconds.remainder(60);
      return '超時 ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    
    // 显示剩余时间
    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);
    final seconds = difference.inSeconds.remainder(60);
    return '剩餘 ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 获取暂停状态的时间文本
  static String _getPausedTimeText(EventModel event) {
    final now = DateTime.now();
    
    // 计算动态结束时间（基于实际开始时间）
    if (event.actualStartTime != null) {
      final taskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
      final targetEndTime = event.actualStartTime!.add(taskDuration);
      final difference = targetEndTime.difference(now);
      
      if (difference.isNegative) {
        // 如果已经超过结束时间
        final overdue = now.difference(targetEndTime);
        final hours = overdue.inHours;
        final minutes = overdue.inMinutes.remainder(60);
        return '已超時 ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
      } else {
        // 显示剩余时间
        final hours = difference.inHours;
        final minutes = difference.inMinutes.remainder(60);
        return '剩餘 ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
      }
    }
    
    // 如果没有实际开始时间，显示原定时间
    return event.timeRange;
  }
}

// -------------------------------------------------------------------------
// Status circle icon on the left
// -------------------------------------------------------------------------
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.status,
    required this.color,
    required this.size,
  });

  final TaskStatus status;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (status == TaskStatus.completed) {
      return Icon(
        Icons.check_circle,
        color: const Color(0xFF8FA69F),
        size: size,
      );
    }

    // 根據狀態選擇圖標
    IconData icon;
    if (status == TaskStatus.inProgress) {
      icon = Icons.radio_button_checked_outlined;
    } else if (status == TaskStatus.overtime) {
      icon = Icons.access_time_filled; // 超時使用時鐘圖標
    } else if (status == TaskStatus.paused) {
      icon = Icons.pause_circle_outline; // 暫停使用暫停圖標
    } else {
      icon = Icons.radio_button_unchecked;
    }

    return Icon(icon, size: size, color: color);
  }
}

// -------------------------------------------------------------------------
// Action button on the right (Start/Stop)
// -------------------------------------------------------------------------
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.status,
    required this.onStart,
    required this.onStop,
    required this.onComplete,
    required this.onContinue,
    required this.onChat,
    required this.buttonHeight,
    required this.buttonWidth,
    required this.borderRadius,
    required this.fontSize,
  });

  final TaskStatus status;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onComplete;
  final VoidCallback onContinue;
  final VoidCallback onChat;
  final double buttonHeight;
  final double buttonWidth;
  final double borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (status == TaskStatus.completed) return const SizedBox.shrink();

    // 按鈕顏色與樣式設定
    Color buttonColor;
    Color textColor = Colors.black87;

    // 根據任務狀態決定按鈕顏色
    if (status == TaskStatus.inProgress || status == TaskStatus.overtime || status == TaskStatus.notStarted || status == TaskStatus.paused) {
      // Stop/Continue 按鈕使用較淺的綠色
      buttonColor = const Color(0xFFCED2C9);
    } else {
      // Start 按鈕使用較暖的奶油色
      buttonColor = const Color(0xFFE3D5CA);
    }

    // 響應式按鈕樣式
    final ButtonStyle buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: buttonColor,
      foregroundColor: textColor,
      elevation: 0,
      padding: EdgeInsets.zero,
      minimumSize: Size(buttonWidth, buttonHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      textStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      ),
    );

    // Start button
    if (status == TaskStatus.notStarted || status == TaskStatus.overdue) {
      return Column(
        mainAxisSize: MainAxisSize.min, // 不撐滿父層
        crossAxisAlignment: CrossAxisAlignment.end, // 右對齊，跟原本一致
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: buttonWidth,
              maxWidth: buttonWidth * 1.5,
              minHeight: buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: onChat, // ← 新 callback
              style: buttonStyle,
              child: const Text('Chat'),
            ),
          ),
          const SizedBox(height: 6), // 垂直間距
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: buttonWidth,
              maxWidth: buttonWidth * 1.5,
              minHeight: buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: onStart,
              style: buttonStyle,
              child: const Text('Start'),
            ),
          ),
        ],
      );
    }

    // Continue button (Paused state)
    if (status == TaskStatus.paused) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: buttonWidth,
              maxWidth: buttonWidth * 1.5,
              minHeight: buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: onChat,
              style: buttonStyle,
              child: const Text('Chat'),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: buttonWidth,
              maxWidth: buttonWidth * 1.5,
              minHeight: buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: onContinue,
              style: buttonStyle,
              child: const Text('Continue'),
            ),
          ),
        ],
      );
    }

    // Stop and Complete buttons (In Progress and Overtime)
    if (status == TaskStatus.inProgress || status == TaskStatus.overtime) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: buttonWidth,
              maxWidth: buttonWidth * 1.5,
              minHeight: buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: onComplete,
              style: buttonStyle,
              child: const Text('Done'),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: buttonWidth,
              maxWidth: buttonWidth * 1.5,
              minHeight: buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: onStop,
              style: buttonStyle,
              child: const Text('Pause'),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
