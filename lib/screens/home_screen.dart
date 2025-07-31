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
  final Set<String> _shownDialogTaskIds = {}; // 記錄已顯示過對話框的任務ID

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
        // 初始化通知服務
        try {
          await NotificationService.instance.initialize();
          // 安排每日報告通知
          await NotificationService.instance.scheduleDailyReportNotification();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('通知服務初始化失敗: $e')));
          }
        }

        // 初始同步
        final uid = context.read<AuthService>().currentUser!.uid;
        try {
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
        
        // 檢查是否有任務需要顯示開始對話框
        // 如果app是由通知打開的，跳過此檢查以避免重複顯示對話框
        if (!AppUsageService.instance.openedByNotification) {
          _checkPendingTaskStart(uid);
        } else {
          if (kDebugMode) {
            print('App由通知打開，跳過pending task start檢查');
          }
        }
        
        // 重置通知打开标志，确保下次resume时正常检查
        AppUsageService.instance.resetNotificationFlag();
      }
    }
  }

  /// 檢查通知排程（App Resume 時調用）
  Future<void> _checkNotificationSchedule(String uid) async {
    try {
      // 修复时区问题：使用台湾时区计算今天的范围
      final now = DateTime.now();
      final localToday = DateTime(now.year, now.month, now.day); // 本地午夜
      final localTomorrow = localToday.add(const Duration(days: 1)); // 本地明天午夜
      
      // 转换为UTC用于Firestore查询
      final start = localToday.toUtc();
      final end = localTomorrow.toUtc();
      
      // 使用 DataPathService 获取正确的 events 集合
      final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
      
      final snap = await eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final allEvents = snap.docs.map(EventModel.fromDoc).toList();
      final events = allEvents.where((event) => event.isActive).toList();
      
      // 過濾出未開始的事件
      final futureEvents = events.where((event) => 
        event.scheduledStartTime.isAfter(now) && !event.isDone
      ).toList();
      
      // 執行通知排程檢查
      if (futureEvents.isNotEmpty) {
        await NotificationScheduler().sync(futureEvents);
        if (kDebugMode) {
          print('App Resume: 檢查了 ${futureEvents.length} 個未來事件的通知排程');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('App Resume 通知檢查失敗: $e');
      }
    }
  }

  /// 檢查是否有任務需要顯示開始對話框（App Resume 時調用）
  Future<void> _checkPendingTaskStart(String uid) async {
    try {
      // 修复时区问题：使用台湾时区计算今天的范围
      final now = DateTime.now();
      final localToday = DateTime(now.year, now.month, now.day); // 本地午夜
      final localTomorrow = localToday.add(const Duration(days: 1)); // 本地明天午夜
      
      // 转换为UTC用于Firestore查询
      final start = localToday.toUtc();
      final end = localTomorrow.toUtc();
      
      // 使用 DataPathService 获取正确的 events 集合
      final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
      
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
        
        // 已經顯示過對話框的任務不再顯示
        if (_shownDialogTaskIds.contains(event.id)) return false;
        
        // 已經顯示過完成提醒對話框的任務不再顯示開始對話框
        if (NotificationHandler.instance.shownCompletionDialogTaskIds.contains(event.id)) return false;
        
        // 只在任務開始時間前後10分鐘內顯示對話框
        final bufferTime = const Duration(minutes: 20);
        final earliestShowTime = event.scheduledStartTime.subtract(bufferTime); // 開始前20分鐘
        final latestShowTime = event.scheduledStartTime.add(bufferTime);       // 開始後20分鐘
        
        // 當前時間必須在時間窗口內
        final inTimeWindow = now.isAfter(event.scheduledStartTime) && now.isBefore(latestShowTime);

        
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
        
        // 設置對話框顯示狀態
        NotificationHandler.instance.setTaskStartDialogShowing(true);
        
        if (mounted) {
          // 顯示任務開始對話框
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => TaskStartDialog(event: mostUrgentTask),
          ).then((_) {
            // 對話框關閉時重置狀態
            NotificationHandler.instance.setTaskStartDialogShowing(false);
          });
          
          if (kDebugMode) {
            print('顯示任務開始對話框: ${mostUrgentTask.title}');
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
        await AnalyticsService().logTaskStarted('event_card');
        break;
      case TaskAction.stop:
        await CalendarService.instance.stopEvent(uid, e);
        break;
      case TaskAction.complete:
        await CalendarService.instance.completeEvent(uid, e);
        break;
      case TaskAction.continue_:
        await CalendarService.instance.continueEvent(uid, e);
        await AnalyticsService().logTaskStarted('event_card_continue');
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
                child: stream == null || _isInitialSync
                    ? const Center(child: CircularProgressIndicator())
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
                                  // 事件列表
                                  ListView.separated(
                                    padding: listPadding,
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) =>
                                        SizedBox(height: listViewSpacing),
                                    itemBuilder: (_, i) => EventCard(
                                        event: list[i],
                                        onAction: (a) => _handleAction(list[i], a),
                                        onOpenChat: () async {
                                          if (mounted) {
                                            // 🎯 實驗數據收集：記錄聊天按鈕點擊
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
                                                      taskDescription: list[i].description, // 新增描述參數
                                                      startTime: list[i].scheduledStartTime,
                                                      uid: uid,
                                                      eventId: list[i].id,
                                                      chatId: chatId,
                                                      entryMethod: ChatEntryMethod.eventCard, // 🎯 新增：事件卡片進入
                                                    ),
                                                    child: ChatScreen(
                                                      taskTitle: list[i].title,
                                                      taskDescription: list[i].description, // 新增描述參數
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        }),
                                  ),
                                  // 同步loading overlay
                                  if (isSyncing)
                                    Container(
                                      color: Colors.white, // Changed from black.withOpacity(0.3)
                                      child: const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              '同步中...',
                                              style: TextStyle(
                                                color: Colors.deepPurple,
                                                fontSize: 16,
                                              ),
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
