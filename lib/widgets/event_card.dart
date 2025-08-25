import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../services/vocab_service.dart';
import '../services/reading_service.dart';
import 'dart:async';

enum TaskAction { start, stop, complete, continue_, reviewStart, reviewEnd }

class EventCard extends StatefulWidget {
  const EventCard(
      {super.key,
      required this.event,
      required this.onAction,
      this.onOpenChat,
      this.isPastEvent = false});

  final EventModel event;
  final void Function(TaskAction a) onAction;
  final void Function()? onOpenChat;
  final bool isPastEvent; // 是否為過去事件（用於控制按鈕顯示）

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
    // 響應式字體大小計算
    final titleFontSize = (18 * responsiveText).clamp(16.0, 22.0);
    final subtitleFontSize = (15 * responsiveText).clamp(14.0, 19.0);
    final pastEventFontSize = (12 * responsiveText).clamp(11.0, 15.0); // Past Event 專用較小字體

    // --- Card background color based on status ---------------------------
    late final Color bg;
    late final Color statusColor;
    late final Color circleColor;

    // 🎯 Past Events 統一使用淺灰色調，不顯示狀態顏色
    if (widget.isPastEvent) {
      bg = const Color(0xFFF5F5F5); // 統一淺灰色背景
      statusColor = const Color(0xFF9E9E9E); // 統一灰色文字
      circleColor = const Color(0xFFBDBDBD); // 統一灰色圓圈
    } else {
      // 檢查是否為測試任務
      final isTestTask = _isTestTitle(widget.event.title);
      
      if (isTestTask) {
        // Test 事件使用特殊顏色 - 淺藍色系
        switch (widget.event.computedStatus) {
          case TaskStatus.inProgress:
            bg = const Color(0xFFE6F3FF); // Light blue
            statusColor = const Color(0xFF4A90E2); // Blue for test in-progress
            circleColor = const Color(0xFF5BA3F5); // Light blue for test in-progress
            break;
          case TaskStatus.overdue:
            bg = const Color(0xFFE6F0FF); // Light blue-ish
            statusColor = const Color(0xFF6B8DD6); // Blue-grey for test overdue
            circleColor = const Color(0xFF7BA3E0); // Light blue-grey for test overdue
            break;
          case TaskStatus.overtime:
            bg = const Color(0xFFE6EFFF); // Light blue-ish
            statusColor = const Color(0xFF5A8BCE); // Blue for test overtime
            circleColor = const Color(0xFF6A95D8); // Blue for test overtime
            break;
          case TaskStatus.completed:
            bg = const Color(0xFFD6E8FF); // Light blue-grey
            statusColor = const Color(0xFF4A7BA7); // Dark blue-grey
            circleColor = const Color(0xFF5A8BC2); // Blue-grey
            break;
          case TaskStatus.paused:
            bg = const Color(0xFFEBF2FF); // Light blue for test paused
            statusColor = const Color(0xFF6A8FCC); // Blue-grey for test paused
            circleColor = const Color(0xFF7A9FDC); // Light blue for test paused
            break;
          case TaskStatus.notStarted:
          default:
            bg = const Color(0xFFEDF4FF); // Light blue
            statusColor = const Color(0xFF5A8BCE); // Blue-grey
            circleColor = const Color(0xFF6A95D8); // Blue
        }
      } else {
        // 一般事件使用原有顏色
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
      }
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
                isPastEvent: widget.isPastEvent,
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
                    // 🎯 Past Events 使用 FutureBuilder 異步載入內容
                    widget.isPastEvent 
                      ? FutureBuilder<String>(
                          future: _generateLearningContentSummary(widget.event),
                          builder: (context, snapshot) {
                            final text = snapshot.data ?? '載入中...';
                            return Text(
                              text,
                              style: TextStyle(
                                fontSize: pastEventFontSize,
                                color: statusColor,
                              ),
                            );
                          },
                        )
                      : Text(
                          _subtitleText(widget.event, isPastEvent: widget.isPastEvent),
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
                onChat: widget.onOpenChat != null ? () => widget.onOpenChat!() : null,
                // Pass in responsive size parameters
                buttonHeight: size.height * 0.045,
                buttonWidth: size.width * 0.2,
                borderRadius: size.width * 0.02,
                fontSize: subtitleFontSize,
                onReviewStart: () => widget.onAction(TaskAction.reviewStart),
                isTestTask: _isTestTitle(widget.event.title),
                isPastEvent: widget.isPastEvent, // 傳遞過去事件標記
              ),
            ],
          ),
        ),
      );
    });
  }

  bool _isTestTitle(String title) {
    final lower = title.toLowerCase().trim();
    final vocabTest = RegExp(r'^vocab[-_]?w\d+[-_]?test$');
    final readingTest = RegExp(r'^reading[-_]?w\d+[-_]?test$');
    return vocabTest.hasMatch(lower) || readingTest.hasMatch(lower);
  }

  static String _subtitleText(EventModel e, {bool isPastEvent = false}) {
    // 🎯 Past Events 顯示學習內容而不是時間範圍
    if (isPastEvent) {
      return '載入中...'; // 暫時顯示，將由 FutureBuilder 替換
    }
    
    return switch (e.computedStatus) {
      TaskStatus.inProgress => _getCountdownText(e),
      TaskStatus.overtime => _getCountdownText(e), // 超時也顯示倒數時間（會顯示超時多久）
      TaskStatus.overdue => 'Overdue',
      TaskStatus.notStarted => e.timeRange,
      TaskStatus.completed => 'Complete',
      TaskStatus.paused => '已暫停 - ${_getPausedTimeText(e)}', // 暫停狀態顯示暫停信息
    };
  }

  /// 生成學習內容摘要（用於過去事件顯示）
  Future<String> _generateLearningContentSummary(EventModel e) async {
    final title = e.title.toLowerCase().trim();
    
    try {
      // 單字任務
      if (title.contains('vocab') || title.contains('單字')) {
        // 解析週次和天數資訊
        final weekDayMatch = RegExp(r'w(\d+)[-_]?d(\d+)').firstMatch(title);
        if (weekDayMatch != null) {
          final week = int.parse(weekDayMatch.group(1)!);
          final day = int.parse(weekDayMatch.group(2)!);
          
          try {
            final vocabs = await VocabService().loadWeeklyVocab(week, day);
            if (vocabs.isNotEmpty) {
              // 顯示前三個單字
              final topThree = vocabs.take(3).map((v) => v.word).where((w) => w.isNotEmpty).toList();
              if (topThree.isNotEmpty) {
                final content = '${topThree.join(', ')}${topThree.length == 3 ? '...' : ''}';
                // 限制長度為10個字，超過則截取並添加省略號
                return content.length > 10 ? '${content.substring(0, 10)}...' : content;
              }
            }
          } catch (e) {
            if (kDebugMode) print('載入單字內容失敗: $e');
          }
          
          final content = '第$week週第$day天單字學習';
          return content.length > 10 ? '${content.substring(0, 10)}...' : content;
        }
        
        // 測驗
        final testMatch = RegExp(r'w(\d+)[-_]?test').firstMatch(title);
        if (testMatch != null) {
          final week = testMatch.group(1);
          final content = '第$week週單字測驗';
          return content.length > 10 ? '${content.substring(0, 10)}...' : content;
        }
        
        final content = '單字學習';
        return content.length > 10 ? '${content.substring(0, 10)}...' : content;
      }
      
      // 閱讀任務
      if (title.contains('reading') || title.contains('閱讀') || title.contains('dyn')) {
        // 解析週次和天數資訊
        final weekDayMatch = RegExp(r'w(\d+)[-_]?d(\d+)').firstMatch(title);
        if (weekDayMatch != null) {
          final week = int.parse(weekDayMatch.group(1)!);
          final day = int.parse(weekDayMatch.group(2)!);
          
          try {
            final articles = await ReadingService().loadDailyArticles(week, day);
            if (articles.isNotEmpty) {
              // 顯示第一篇文章標題
              final firstTitle = articles.first.title;
              final content = firstTitle.length > 25 ? '${firstTitle.substring(0, 25)}...' : firstTitle;
              // 限制長度為10個字，超過則截取並添加省略號
              return content.length > 10 ? '${content.substring(0, 10)}...' : content;
            }
          } catch (e) {
            if (kDebugMode) print('載入閱讀內容失敗: $e');
          }
          
          final content = '第$week週第$day天文章閱讀';
          return content.length > 10 ? '${content.substring(0, 10)}...' : content;
        }
        
        // 測驗
        final testMatch = RegExp(r'w(\d+)[-_]?test').firstMatch(title);
        if (testMatch != null) {
          final week = testMatch.group(1);
          final content = '第$week週閱讀測驗';
          return content.length > 10 ? '${content.substring(0, 10)}...' : content;
        }
        
        final content = '文章閱讀';
        return content.length > 10 ? '${content.substring(0, 10)}...' : content;
      }
      
      // 其他任務，顯示描述或標題
      if (e.description != null && e.description!.isNotEmpty) {
        // 如果描述太長，截取前30個字元
        final desc = e.description!;
        final content = desc.length > 30 ? '${desc.substring(0, 30)}...' : desc;
        // 限制長度為10個字，超過則截取並添加省略號
        return content.length > 10 ? '${content.substring(0, 10)}...' : content;
      }
      
      // 最後回退到時間範圍
      final content = e.timeRange;
      return content.length > 10 ? '${content.substring(0, 10)}...' : content;
      
    } catch (err) {
      if (kDebugMode) print('生成學習內容摘要失敗: $err');
      return widget.event.timeRange; // 回退到時間範圍
    }
  }

  /// 計算並返回倒數時間文本
  static String _getCountdownText(EventModel event) {
    final now = DateTime.now();
    
    // 计算动态结束时间
    DateTime targetEndTime;
    DateTime referenceTime = now;
    
    if (event.actualStartTime != null) {
      if (event.pauseAt != null && event.resumeAt != null) {
        // 🎯 修复：正确处理暂停后继续的时间计算
        // 原定任务时长
        final originalTaskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
        // 已经工作的时间（从开始到暂停）
        final workedDuration = event.pauseAt!.difference(event.actualStartTime!);
        // 剩余工作时间 = 原定任务时长 - 已经工作的时间
        final remainingWorkDuration = originalTaskDuration - workedDuration;
        // 调整后的结束时间 = 继续时间 + 剩余工作时间
        targetEndTime = event.resumeAt!.add(remainingWorkDuration);
        

      } else if (event.pauseAt != null) {
        // 如果只有暂停时间但没有继续时间（暂停状态）
        // 原定任务时长
        final originalTaskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
        // 已经工作的时间
        final workedDuration = event.pauseAt!.difference(event.actualStartTime!);
        // 剩余工作时间 = 原定任务时长 - 已经工作的时间
        final remainingWorkDuration = originalTaskDuration - workedDuration;
        // 调整后的结束时间 = 当前时间 + 剩余工作时间
        targetEndTime = now.add(remainingWorkDuration);
        
      } else {
        // 没有暂停，使用原来的逻辑
        final taskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
        targetEndTime = event.actualStartTime!.add(taskDuration);
        
      }
    } else {
      // 如果没有实际开始时间，使用原定结束时间
      targetEndTime = event.scheduledEndTime;
      
      if (kDebugMode) {
        print('_getCountdownText: 未开始计算: ${event.title}');
        print('  原定结束时间: $targetEndTime');
      }
    }
    
    final difference = targetEndTime.difference(referenceTime);
    
    if (difference.isNegative) {
      // 如果已经超过结束时间，显示超时
      final overdue = referenceTime.difference(targetEndTime);
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
    // 🎯 使用专门的pauseAt字段作为暂停时间
    final pauseTime = event.pauseAt ?? DateTime.now();
    
    if (kDebugMode) {
      print('_getPausedTimeText: ${event.title}, pauseAt: $pauseTime');
    }
    
    // 计算动态结束时间（基于实际开始时间）
    if (event.actualStartTime != null) {
      // 🎯 修复：正确处理暂停状态的剩余时间计算
      // 原定任务时长
      final originalTaskDuration = event.scheduledEndTime.difference(event.scheduledStartTime);
      // 已经工作的时间（从开始到暂停）
      final workedDuration = pauseTime.difference(event.actualStartTime!);
      // 剩余工作时间 = 原定任务时长 - 已经工作的时间
      final remainingWorkDuration = originalTaskDuration - workedDuration;
      
      if (remainingWorkDuration.isNegative) {
        // 如果已经超过原定工作时间
        final overdue = workedDuration - originalTaskDuration;
        final hours = overdue.inHours;
        final minutes = overdue.inMinutes.remainder(60);
        return '已超時 ${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
      } else {
        // 显示剩余工作时间
        final hours = remainingWorkDuration.inHours;
        final minutes = remainingWorkDuration.inMinutes.remainder(60);
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
    this.isPastEvent = false,
  });

  final TaskStatus status;
  final Color color;
  final double size;
  final bool isPastEvent;

  @override
  Widget build(BuildContext context) {
    // 🎯 Past Events 統一使用簡單的圓圈圖標，不顯示狀態差異
    if (isPastEvent) {
      return Icon(
        Icons.radio_button_unchecked,
        color: color,
        size: size,
      );
    }

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
class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.status,
    required this.onStart,
    required this.onStop,
    required this.onComplete,
    required this.onContinue,
    this.onChat,
    required this.buttonHeight,
    required this.buttonWidth,
    required this.borderRadius,
    required this.fontSize,
    required this.onReviewStart,
    required this.isTestTask,
    required this.isPastEvent,
    super.key,
  });

  final TaskStatus status;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onComplete;
  final VoidCallback onContinue;
  final VoidCallback? onChat;
  final double buttonHeight;
  final double buttonWidth;
  final double borderRadius;
  final double fontSize;
  final VoidCallback onReviewStart;
  final bool isTestTask;
  final bool isPastEvent; // 是否為過去事件

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isProcessing = false; // 防止重複點擊的通用狀態
  
  /// 包裝按鈕回調以防止重複點擊
  VoidCallback? _wrapCallback(VoidCallback? callback) {
    if (callback == null || _isProcessing) return null;
    
    return () async {
      if (_isProcessing) return;
      
      setState(() {
        _isProcessing = true;
      });
      
      try {
        callback();
      } finally {
        // 延遲重置狀態，避免連續快速點擊
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    // Past Events 只顯示「開始複習」按鈕
    if (widget.isPastEvent) {
      // 測驗型任務在 Past Events 中不顯示任何按鈕
      if (widget.isTestTask) return const SizedBox.shrink();
      
      // 只顯示「開始複習」按鈕
      final Color buttonColor = const Color(0xFFD7DFE0); // 與底部 Daily Report 顏色接近
      final Color textColor = Colors.black87;
      final ButtonStyle buttonStyle = ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: textColor,
        elevation: 0,
        padding: EdgeInsets.zero,
                minimumSize: Size(widget.buttonWidth, widget.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        textStyle: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w500,
        ),
      );
      
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.buttonWidth,
          maxWidth: widget.buttonWidth * 1.5,
          minHeight: widget.buttonHeight,
        ),
        child: ElevatedButton(
          onPressed: _wrapCallback(widget.onReviewStart),
          style: buttonStyle,
          child: const Text('開始複習'),
        ),
      );
    }
    
    if (widget.status == TaskStatus.completed) {
      // 測驗型任務（reading-test/vocab-test）不顯示複習按鈕
      if (widget.isTestTask) return const SizedBox.shrink();

      // 完成狀態：僅顯示「開始複習」，離開任務頁時自動結束
      final Color buttonColor = const Color(0xFFD7DFE0); // 與底部 Daily Report 顏色接近
      final Color textColor = Colors.black87;
      final ButtonStyle buttonStyle = ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: textColor,
        elevation: 0,
        padding: EdgeInsets.zero,
        minimumSize: Size(widget.buttonWidth, widget.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        textStyle: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w500,
        ),
      );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.buttonWidth,
              maxWidth: widget.buttonWidth * 1.5,
              minHeight: widget.buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: _wrapCallback(widget.onReviewStart),
              style: buttonStyle,
              child: const Text('開始複習'),
            ),
          ),
        ],
      );
    }

    // 按鈕顏色與樣式設定
    Color buttonColor;
    Color textColor = Colors.black87;

    // 根據任務狀態決定按鈕顏色
    if (widget.status == TaskStatus.inProgress || widget.status == TaskStatus.overtime || widget.status == TaskStatus.notStarted || widget.status == TaskStatus.paused) {
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
      minimumSize: Size(widget.buttonWidth, widget.buttonHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      textStyle: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w500,
      ),
    );

    // Start button
    if (widget.status == TaskStatus.notStarted || widget.status == TaskStatus.overdue) {
      return Column(
        mainAxisSize: MainAxisSize.min, // 不撐滿父層
        crossAxisAlignment: CrossAxisAlignment.end, // 右對齊，跟原本一致
        children: [
          // 只有當onChat不為null且不是測試任務時才顯示聊天按鈕
          if (widget.onChat != null && !widget.isTestTask) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.buttonWidth,
                maxWidth: widget.buttonWidth * 1.5,
                minHeight: widget.buttonHeight,
              ),
              child: ElevatedButton(
                onPressed: _wrapCallback(widget.onChat),
                style: buttonStyle,
                child: const Text('需要動力'),
              ),
            ),
            const SizedBox(height: 6), // 垂直間距
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.buttonWidth,
              maxWidth: widget.buttonWidth * 1.5,
              minHeight: widget.buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: _wrapCallback(widget.onStart),
              style: buttonStyle,
              child: const Text('開始任務'),
            ),
          ),
        ],
      );
    }

    // Continue button (Paused state)
    if (widget.status == TaskStatus.paused) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 只有當onChat不為null且不是測試任務時才顯示聊天按鈕
          if (widget.onChat != null && !widget.isTestTask) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.buttonWidth,
                maxWidth: widget.buttonWidth * 1.5,
                minHeight: widget.buttonHeight,
              ),
              child: ElevatedButton(
                onPressed: _wrapCallback(widget.onChat),
                style: buttonStyle,
                child: const Text('需要動力'),
              ),
            ),
            const SizedBox(height: 6),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.buttonWidth,
              maxWidth: widget.buttonWidth * 1.5,
              minHeight: widget.buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: _wrapCallback(widget.onContinue),
              style: buttonStyle,
              child: const Text('繼續任務'),
            ),
          ),
        ],
      );
    }

    // Stop and Complete buttons (In Progress and Overtime)
    if (widget.status == TaskStatus.inProgress || widget.status == TaskStatus.overtime) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.buttonWidth,
              maxWidth: widget.buttonWidth * 1.5,
              minHeight: widget.buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: _wrapCallback(widget.onComplete),
              style: buttonStyle,
              child: const Text('完成'),
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.buttonWidth,
              maxWidth: widget.buttonWidth * 1.5,
              minHeight: widget.buttonHeight,
            ),
            child: ElevatedButton(
              onPressed: _wrapCallback(widget.onStop),
              style: buttonStyle,
              child: const Text('暫停任務'),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
