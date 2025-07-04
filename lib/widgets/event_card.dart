import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../models/enums.dart';

enum TaskAction { start, stop, complete }

class EventCard extends StatelessWidget {
  const EventCard(
      {super.key,
      required this.event,
      required this.onAction,
      required this.onOpenChat});

  final EventModel event;
  final void Function(TaskAction a) onAction;
  final void Function() onOpenChat;

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

    switch (event.status) {
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
      case TaskStatus.completed:
        bg = const Color(0xFFCBD0C9); // Desaturated blue-grey
        statusColor = const Color(0XFF6F7C71);
        circleColor = const Color(0xFF99A59D);
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
        opacity: event.status == TaskStatus.completed ? 0.85 : 1,
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
                status: event.computedStatus,
                color: circleColor,
                size: iconSize,
                onComplete: event.computedStatus == TaskStatus.inProgress
                    ? () => onAction(TaskAction.complete)
                    : null,
              ),
              SizedBox(width: horizontalSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: size.height * 0.005),
                    Text(
                      _subtitleText(event),
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: statusColor, // Grey for other text
                      ),
                    ),
                  ],
                ),
              ),
              _ActionButton(
                status: event.computedStatus,
                onStart: () => onAction(TaskAction.start),
                onStop: () => onAction(TaskAction.stop),
                onChat: () => onOpenChat(),
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
      TaskStatus.inProgress => 'In Progress',
      TaskStatus.overdue => 'Overdue',
      TaskStatus.notStarted => e.timeRange,
      TaskStatus.completed => 'Complete',
    };
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
    this.onComplete,
  });

  final TaskStatus status;
  final Color color;
  final double size;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    if (status == TaskStatus.completed) {
      return Icon(
        Icons.check_circle,
        color: const Color(0xFF8FA69F),
        size: size,
      );
    }

    final icon = status == TaskStatus.inProgress
        ? Icons.radio_button_checked_outlined
        : Icons.radio_button_unchecked;

    final iconWidget = Icon(icon, size: size, color: color);

    if (status == TaskStatus.inProgress && onComplete != null) {
      return InkWell(
        onTap: onComplete,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: iconWidget,
        ),
      );
    }
    return iconWidget;
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
    required this.onChat,
    required this.buttonHeight,
    required this.buttonWidth,
    required this.borderRadius,
    required this.fontSize,
  });

  final TaskStatus status;
  final VoidCallback onStart;
  final VoidCallback onStop;
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
    if (status == TaskStatus.inProgress || status == TaskStatus.notStarted) {
      // Stop 按鈕使用較淺的綠色
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

    // Stop button (In Progress)
    if (status == TaskStatus.inProgress) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: buttonWidth,
          maxWidth: buttonWidth * 1.5,
          minHeight: buttonHeight,
        ),
        child: ElevatedButton(
          onPressed: onStop,
          style: buttonStyle,
          child: const Text('Stop'),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
