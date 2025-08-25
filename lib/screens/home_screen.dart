import 'package:flutter/material.dart';
import 'package:momentum/providers/chat_provider.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../providers/events_provider.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../widgets/event_card.dart';
import '../widgets/task_start_dialog.dart';
import '../screens/chat_screen.dart';
import '../screens/daily_report_screen.dart';
import '../services/notification_service.dart';
import '../services/notification_handler.dart';
import '../services/app_usage_service.dart';
import '../services/data_path_service.dart';
import '../services/experiment_config_service.dart';
import '../services/task_router_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/analytics_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<EventModel> _cached = const [];
  bool _isInitialSync = true;
  bool _isFirstTimeSetup = true; // 第一次设置loading状态
  final Set<String> _shownDialogTaskIds = {}; // 記錄已顯示過對話框的任務ID
  bool _isExperimentGroup = false; // 用户是否为实验组
  bool _isOpeningChat = false; // 防止重複點擊聊天按鈕

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final googleAccount = AuthService.instance.googleAccount;
      if (googleAccount == null) {
        // 只 sign out，不要用 Navigator 跳頁
        await AuthService.instance.signOut();
        // AuthGate 會自動顯示 SignInScreen
      } else {
        // 第一次设置loading状态
        setState(() {
          _isFirstTimeSetup = true;
        });

        // 获取用户当前日期的实验组别
        final uid = context.read<AuthService>().currentUser!.uid;
        try {
          if (kDebugMode) {
            print('正在分配用户组别...');
          }
          _isExperimentGroup = await ExperimentConfigService.instance.isExperimentGroup(uid);
          if (mounted) {
            setState(() {});
          }
        } catch (e) {
          if (kDebugMode) {
            print('获取用户当前日期实验组别失败: $e');
          }
          // 默认设为实验组
          _isExperimentGroup = true;
          if (mounted) {
            setState(() {});
          }
        }

        // 初始化通知服務
        try {
          if (kDebugMode) {
            print('正在初始化通知服务...');
          }
          await NotificationService.instance.initialize();
          // 注意：每日報告通知由 AuthService 在新用戶建立時統一排定15天，此處不重複排定
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('通知服務初始化失敗: $e')));
          }
        }

        // 初始同步
        try {
          if (kDebugMode) {
            print('正在抓取任务数据...');
          }
          // 僅同步當天（事件通知的排程僅在「新用戶建立」時一次性完成）
          await CalendarService.instance.syncToday(uid);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Initial sync failed: $e')));
          }
        } finally {
          if (mounted) {
            setState(() {
              _isInitialSync = false;
              _isFirstTimeSetup = false; // 完成第一次设置
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      final uid = context.read<AuthService>().currentUser?.uid;
      if (uid != null) {
        // 重新检查当前日期的实验组别（处理跨日情况）
        _updateExperimentGroup(uid);
        
        // 強制刷新事件提供者以更新日期範圍（處理跨日情況）
        context.read<EventsProvider>().refreshToday(context.read<AuthService>().currentUser!);
        
        // 執行日曆同步
        CalendarService.instance.resumeSync(uid).catchError((e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Resume sync failed: $e')));
          }
        });
        
        // 額外的通知排程檢查（處理用戶手動修改 Google Calendar 的情況）
        _checkNotificationSchedule(uid);
        
        // 检查是否有任務需要顯示開始對話框（实验组和对照组都显示）
        // 如果app是由通知打開的，跳过此检查，因为notification_handler会处理对话框显示
        if (AppUsageService.instance.openedByNotification) {
          if (kDebugMode) {
            print('App由通知打開，跳过pending task检查，由notification_handler处理');
          }
        } else {
          _checkPendingTaskStart(uid, forceShow: false);
        }
        
        // 重置通知打开标志，确保下次resume时正常检查
        AppUsageService.instance.resetNotificationFlag();
      }
    }
  }

  /// 更新当前日期的实验组别
  Future<void> _updateExperimentGroup(String uid) async {
    try {
      final isExperiment = await ExperimentConfigService.instance.isExperimentGroup(uid);
      if (mounted && _isExperimentGroup != isExperiment) {
        setState(() {
          _isExperimentGroup = isExperiment;
        });
        if (kDebugMode) {
          print('实验组别已更新: ${isExperiment ? '实验组' : '对照组'}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('更新实验组别失败: $e');
      }
    }
  }

  /// 檢查通知排程（App Resume 時調用）
  Future<void> _checkNotificationSchedule(String uid) async {
    try {
      // 修復時區：以本地午夜作為每日日界線
      final now = DateTime.now();
      
      for (int i = 0; i <= 2; i++) {
        final targetDay = DateTime(now.year, now.month, now.day).add(Duration(days: i));
        final startOfDayLocal = targetDay; // 本地日界線
        final endOfDayLocal = startOfDayLocal.add(const Duration(days: 1));
        final startUtc = startOfDayLocal.toUtc();
        final endUtc = endOfDayLocal.toUtc();

        // 依目標日期取得正確集合（w1/w2）
        final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, targetDay);
        final snap = await eventsCollection
            .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startUtc))
            .where('scheduledStartTime', isLessThan: Timestamp.fromDate(endUtc))
            .orderBy('scheduledStartTime')
            .get();

        final allEvents = snap.docs.map(EventModel.fromDoc).toList();
        final activeEvents = allEvents.where((e) => e.isActive).toList();

        // 今日：只補 now 之後；未來兩天：補當日全部未完成事件
        final toSchedule = activeEvents.where((e) {
          if (i == 0) {
            return !e.isDone && e.scheduledStartTime.isAfter(now);
          }
          return !e.isDone;
        }).toList();

        if (toSchedule.isNotEmpty) {
          await NotificationScheduler().sync(toSchedule);
          if (kDebugMode) {
            print('App Resume: 補排 ${targetDay.toString().substring(0,10)} 的 ${toSchedule.length} 個事件通知');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('App Resume 通知檢查失敗: $e');
      }
    }
  }

  /// 檢查是否有任務需要顯示開始對話框（App Resume 時調用）
  Future<void> _checkPendingTaskStart(String uid, {bool forceShow = false}) async {
    try {
      // 修复时区问题：使用台湾时区计算今天的范围
      final now = DateTime.now();
      final localToday = DateTime(now.year, now.month, now.day); // 本地午夜
      final localTomorrow = localToday.add(const Duration(days: 1)); // 本地明天午夜
      
      // 转换为UTC用于Firestore查询
      final start = localToday.toUtc();
      final end = localTomorrow.toUtc();
      
      // 使用 DataPathService 获取当前日期的 events 集合
      final eventsCollection = await DataPathService.instance.getDateEventsCollection(uid, now);
      
      final snap = await eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final allEvents = snap.docs.map(EventModel.fromDoc).toList();
      final events = allEvents.where((event) => event.isActive).toList();
      
      // 找到應該開始但還沒開始的任務
      final pendingEvents = events.where((event) {
        // 任務還沒完成
        if (event.isDone) return false;
        
        // 任務還沒實際開始
        if (event.actualStartTime != null) return false;
        
        // 如果强制显示（通过通知打开），跳过已显示对话框的检查
        if (!forceShow) {
          // 已經顯示過對話框的任務不再顯示
          if (_shownDialogTaskIds.contains(event.id)) return false;
          
          // 已經顯示過完成提醒對話框的任務不再顯示開始對話框
          if (NotificationHandler.instance.shownCompletionDialogTaskIds.contains(event.id)) return false;
        }
        const beforeBuffer = Duration(minutes: 10); // 開始前10分鐘
        const afterBuffer = Duration(minutes: 30);  // 開始後30分鐘 (原為20分鐘)
        final earliestShowTime = event.scheduledStartTime.subtract(beforeBuffer); // 開始前10分鐘
        final latestShowTime = event.scheduledStartTime.add(afterBuffer);         // 開始後30分鐘
        
        // 當前時間必須在時間窗口內
        final inTimeWindow = now.isAfter(earliestShowTime) && now.isBefore(latestShowTime);

        
        return inTimeWindow;
      }).toList();
      
      if (pendingEvents.isNotEmpty) {
        // 检查是否已有TaskStartDialog在显示
        if (NotificationHandler.instance.isTaskStartDialogShowing) {
          if (kDebugMode) {
            print('已有TaskStartDialog在顯示，跳過pending task檢查');
          }
          return;
        }
        
        // 检查是否在聊天页面
        if (context.findAncestorWidgetOfExactType<ChatScreen>() != null) {
          if (kDebugMode) {
            print('當前在聊天頁面，不顯示pending task的TaskStartDialog');
          }
          return;
        }
        
        // 選擇最早應該開始的任務
        pendingEvents.sort((a, b) => a.scheduledStartTime.compareTo(b.scheduledStartTime));
        final mostUrgentTask = pendingEvents.first;
        
        // 記錄已顯示過對話框
        _shownDialogTaskIds.add(mostUrgentTask.id);
        
        // 檢查當前日期的用戶組別
        bool isControlGroup = false;
        try {
          isControlGroup = await ExperimentConfigService.instance.isControlGroup(uid);
        } catch (e) {
          if (kDebugMode) {
            print('檢查用戶組別失敗: $e');
          }
        }
        
        // 設置對話框顯示狀態
        NotificationHandler.instance.setTaskStartDialogShowing(true);
        
        if (mounted) {
          // 顯示任務開始對話框
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => TaskStartDialog(event: mostUrgentTask, isControlGroup: isControlGroup),
          ).then((_) {
            // 對話框關閉時重置狀態
            NotificationHandler.instance.setTaskStartDialogShowing(false);
          });
          
          if (kDebugMode) {
            print('顯示任務開始對話框: ${mostUrgentTask.title}, isControlGroup: $isControlGroup');
          }
        } else {
          // 如果context不可用，重置狀態
          NotificationHandler.instance.setTaskStartDialogShowing(false);
        }
      }
      
      // 清理已完成或已開始的任務ID（避免集合無限增長）
      if (events.isNotEmpty) {
        _shownDialogTaskIds.removeWhere((taskId) {
          try {
            final event = events.firstWhere((e) => e.id == taskId);
            return event.isDone || event.actualStartTime != null;
          } catch (e) {
            // 如果找不到事件，從集合中移除該ID
            return true;
          }
        });
        
        // 同时清理NotificationHandler中的记录
        final eventIds = events.map((e) => e.id).toList();
        NotificationHandler.instance.cleanupCompletionDialogTaskIds(eventIds);
      }
    } catch (e) {
      if (kDebugMode) {
        print('檢查待開始任務失敗: $e');
      }
    }
  }

  Future<void> _handleAction(EventModel e, TaskAction action) async {
    final uid = context.read<AuthService>().currentUser!.uid;
    switch (action) {
      case TaskAction.start:
        await CalendarService.instance.startEvent(uid, e);
        // 跳转到相应的任务页面，source 为 'home_screen'
        if (mounted) {
          TaskRouterService().navigateToTaskPage(context, e, source: 'home_screen');
        }
        break;
      case TaskAction.stop:
        await CalendarService.instance.stopEvent(uid, e);
        break;
      case TaskAction.complete:
        await CalendarService.instance.completeEvent(uid, e);
        break;
      case TaskAction.continue_:
        await CalendarService.instance.continueEvent(uid, e);
        // 跳转到相应的任务页面，source 为 'home_screen_continue'
        if (mounted) {
          TaskRouterService().navigateToTaskPage(context, e, source: 'home_screen_continue');
        }
        break;
      case TaskAction.reviewStart:
        await ExperimentEventHelper.recordReviewStart(uid: uid, eventId: e.id);
        await AnalyticsService().logEvent('review_started', parameters: {
          'source': 'event_card',
        });
        if (mounted) {
          TaskRouterService().navigateToTaskPage(context, e, source: 'home_screen_review');
        }
        break;
      case TaskAction.reviewEnd:
        await ExperimentEventHelper.recordReviewEnd(uid: uid, eventId: e.id);
        await AnalyticsService().logEvent('review_ended', parameters: {
          'source': 'event_card',
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = context.watch<EventsProvider>().stream;
    final size = MediaQuery.of(context).size;
    final responsiveText = MediaQuery.textScalerOf(context).scale(1.0);

    // Calculate responsive padding based on screen width
    final horizontalPadding = size.width * 0.05; // 5% of screen width
    final verticalPadding = size.height * 0.02; // 2% of screen height

    // Calculate responsive sizes
    final iconSize = size.width * 0.05 > 24 ? 24.0 : size.width * 0.05;
    final titleFontSize = (28 * responsiveText).clamp(22.0, 36.0);
    final buttonHeight = size.height * 0.06; // 6% of screen height

    return Scaffold(
      backgroundColor:
          const Color.fromARGB(255, 255, 250, 243), // Light cream background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: size.height * 0.07, // 7% of screen height
        leadingWidth: 0,
        title: Row(
          children: [
            Icon(Icons.diamond_outlined,
                color: Colors.deepPurple, size: iconSize),
            SizedBox(width: size.width * 0.02),
            Text("home page",
                style: TextStyle(
                    fontSize: (16 * responsiveText).clamp(14.0, 20.0),
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          // Responsive spacing based on available height
          final verticalSpacing = constraints.maxHeight * 0.02;
          final listViewSpacing = constraints.maxHeight * 0.015;
          final listPadding = EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          );

          return Column(
            children: [
              SizedBox(height: verticalSpacing),
              
              Text("Today's Tasks",
                  style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3A4A46))),
              SizedBox(height: verticalSpacing),
              Expanded(
                child: stream == null || _isInitialSync || _isFirstTimeSetup
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                            ),
                          ],
                        ),
                      )
                    : StreamBuilder<List<EventModel>>(
                        stream: stream,
                        builder: (_, snap) {
                          if (snap.hasData && snap.data!.isNotEmpty) {
                            _cached = snap.data!;
                          }
                          final list = _cached;
                          if (list.isEmpty) {
                            return const Center(child: Text('No tasks today.'));
                          }

                          // 🎯 在同步时显示带有半透明overlay的loading状态
                          return ListenableBuilder(
                            listenable: CalendarService.instance,
                            builder: (context, child) {
                              final isSyncing = CalendarService.instance.isSyncing;
                              
                              return Stack(
                                children: [
                                  // 事件列表 + Past Events 區塊
                                  ListView(
                                    padding: listPadding,
                                    children: [
                                      // 今日事件
                                      ...List.generate(list.length, (i) => Padding(
                                        padding: EdgeInsets.only(bottom: listViewSpacing),
                                        child: EventCard(
                                        event: list[i],
                                        onAction: (a) => _handleAction(list[i], a),
                                        onOpenChat: _isExperimentGroup ? () async {
                                          if (mounted) {
                                            if (_isOpeningChat) return;
                                            _isOpeningChat = true;
                                            try {
                                              final uid = context.read<AuthService>().currentUser?.uid;
                                              if (uid != null) {
                                                final chatId = ExperimentEventHelper.generateChatId(list[i].id, DateTime.now());
                                                await ExperimentEventHelper.recordChatTrigger(
                                                  uid: uid,
                                                  eventId: list[i].id,
                                                  chatId: chatId,
                                                );
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => ChangeNotifierProvider(
                                                      create: (_) => ChatProvider(
                                                        taskTitle: list[i].title,
                                                          taskDescription: list[i].description,
                                                        startTime: list[i].scheduledStartTime,
                                                        uid: uid,
                                                        eventId: list[i].id,
                                                        chatId: chatId,
                                                          entryMethod: ChatEntryMethod.eventCard,
                                                          dayNumber: list[i].dayNumber,
                                                      ),
                                                      child: ChatScreen(
                                                        taskTitle: list[i].title,
                                                          taskDescription: list[i].description,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } finally {
                                                Future.delayed(const Duration(milliseconds: 500), () {
                                                  if (mounted) {
                                                    setState(() { _isOpeningChat = false; });
                                                  }
                                                });
                                              }
                                            }
                                          } : null,
                                        ),
                                      )),

                                      SizedBox(height: listViewSpacing * 1.5),
                                      // Past Events 區塊
                                      Padding(
                                        padding: EdgeInsets.symmetric(vertical: listViewSpacing),
                                        child: Text(
                                          'Past Events',
                                          style: TextStyle(
                                            fontSize: (18 * responsiveText).clamp(16.0, 22.0),
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF3A4A46),
                                          ),
                                        ),
                                      ),
                                      StreamBuilder<List<EventModel>>(
                                        stream: context.read<EventsProvider>().getPastEventsStream(context.read<AuthService>().currentUser!),
                                        builder: (context, pastSnap) {
                                          final past = (pastSnap.data ?? []).where((e) => e.id.isNotEmpty).toList();
                                          if (past.isEmpty) {
                                            return const Text('No past events this week.');
                                          }
                                          return Column(
                                            children: past.map((e) => Padding(
                                              padding: EdgeInsets.only(bottom: listViewSpacing),
                                              child: EventCard(
                                                event: e,
                                                onAction: (a) => _handleAction(e, a),
                                                isPastEvent: true, // 標記為過去事件
                                                onOpenChat: _isExperimentGroup ? () async {
                                                  if (mounted) {
                                                    if (_isOpeningChat) return;
                                                    _isOpeningChat = true;
                                                    try {
                                                      final uid = context.read<AuthService>().currentUser?.uid;
                                                      if (uid != null) {
                                                        final chatId = ExperimentEventHelper.generateChatId(e.id, DateTime.now());
                                                        await ExperimentEventHelper.recordChatTrigger(
                                                          uid: uid,
                                                          eventId: e.id,
                                                          chatId: chatId,
                                                        );
                                                        Navigator.of(context).push(
                                                          MaterialPageRoute(
                                                            builder: (_) => ChangeNotifierProvider(
                                                              create: (_) => ChatProvider(
                                                                taskTitle: e.title,
                                                                taskDescription: e.description,
                                                                startTime: e.scheduledStartTime,
                                                                uid: uid,
                                                                eventId: e.id,
                                                                chatId: chatId,
                                                                entryMethod: ChatEntryMethod.eventCard,
                                                                dayNumber: e.dayNumber,
                                                              ),
                                                              child: ChatScreen(
                                                                taskTitle: e.title,
                                                                taskDescription: e.description,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }
                                            } finally {
                                              Future.delayed(const Duration(milliseconds: 500), () {
                                                if (mounted) {
                                                          setState(() { _isOpeningChat = false; });
                                                }
                                              });
                                            }
                                          }
                                                } : null,
                                              ),
                                            )).toList(),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  // 同步loading overlay
                                  if (isSyncing)
                                    Container(
                                      color: const Color.fromARGB(255, 255, 250, 243),
                                      child: const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          );
                        },
                      ),
              ),
              // 按鈕區域
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: size.height * 0.01,
                ),
                child: Column(
                  children: [
                    // Daily Report 按鈕
                    Container(
                      width: double.infinity,
                      height: buttonHeight,
                      margin: EdgeInsets.only(bottom: size.height * 0.01),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const DailyReportScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD7DFE0), // Light grey-blue
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(size.width * 0.06),
                          ),
                        ),
                        child: Text('Daily Report',
                            style: TextStyle(
                                fontSize: (14 * responsiveText).clamp(12.0, 18.0),
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: size.height * 0.02),
            ],
          );
        }),
      ),
    );
  }
}
