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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/analytics_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// 靜態方法：重新整理commit plans顯示
  static Future<void> refreshCommitPlans(BuildContext context, String uid) async {
    final state = context.findAncestorStateOfType<_HomeScreenState>();
    if (state != null) {
      await state._loadCommitPlanTasks(uid);
    }
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<EventModel> _cached = const [];
  List<EventModel> _commitPlanTasks = []; // 有commit plan但未完成的任務
  List<Map<String, dynamic>> _commitPlanData = []; // 儲存commit plan的詳細資料
  bool _isInitialSync = true;
  final Set<String> _shownDialogTaskIds = {}; // 記錄已顯示過對話框的任務ID
  bool _isLoadingCommitPlans = false; // 防止重複載入commit plans
  DateTime? _lastCommitPlanLoadTime; // 記錄上次載入時間

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
          // 載入有commit plan的任務
          await _loadCommitPlanTasks(uid);
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
        
        // 載入有commit plan的任務（帶節流機制）
        final now = DateTime.now();
        if (_lastCommitPlanLoadTime == null || 
            now.difference(_lastCommitPlanLoadTime!).inSeconds > 5) {
          _lastCommitPlanLoadTime = now;
          _loadCommitPlanTasks(uid);
        }
        
        // 重置通知打开标志，确保下次resume时正常检查
        AppUsageService.instance.resetNotificationFlag();
      }
    }
  }

  /// 檢查通知排程（App Resume 時調用）
  Future<void> _checkNotificationSchedule(String uid) async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 1));
      
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events');
      
      final snap = await col
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final events = snap.docs.map(EventModel.fromDoc).toList();
      
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

  /// 查詢有commit plan但未完成的任務及其commit plan內容
  Future<void> _loadCommitPlanTasks(String uid) async {
    if (_isLoadingCommitPlans) return; // 防止重複呼叫
    _isLoadingCommitPlans = true;
    
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 1));
      
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events');
      
      final snap = await col
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final events = snap.docs.map(EventModel.fromDoc).toList();
      
      final List<Map<String, dynamic>> commitPlanData = [];
      
      // 檢查每個未完成的事件是否有commit plan
      for (final event in events) {
        // 只檢查未完成、活躍且從未被移動或刪除過的事件
        if (event.isDone || !event.isActive) continue;
        
        // 查詢chats sub-collection，獲取最新的有commit plan的聊天記錄
        final chatsSnap = await col
            .doc(event.id)
            .collection('chats')
            .where('commit_plan', isEqualTo: true)
            .get();
            
        // 在内存中排序并获取最新的记录
        final chatDocs = chatsSnap.docs;
        if (chatDocs.isNotEmpty) {
          chatDocs.sort((a, b) {
            final aTime = (a.data()['start_time'] as Timestamp).toDate();
            final bTime = (b.data()['start_time'] as Timestamp).toDate();
            return bTime.compareTo(aTime); // 降序排序
          });
        
                  // 使用排序后的第一条记录
          final chatDoc = chatDocs.first;
          final chatData = chatDoc.data();
          final commitPlanText = chatData['commit_plan_text'] ?? ''; // commit plan文本字段
          
          commitPlanData.add({
            'event': event,
            'commitPlan': commitPlanText,
            'chatId': chatDoc.id,
          });
        }
      }
      
      if (mounted) {
        setState(() {
          _commitPlanTasks = commitPlanData.map((data) => data['event'] as EventModel).toList();
          _commitPlanData = commitPlanData; // 儲存完整的commit plan資料
        });
      }
      
      if (kDebugMode) {
        print('Loaded ${commitPlanData.length} tasks with commit plans');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading commit plan tasks: $e');
      }
    } finally {
      _isLoadingCommitPlans = false; // 重置載入狀態
    }
  }

  /// 檢查是否有任務需要顯示開始對話框（App Resume 時調用）
  Future<void> _checkPendingTaskStart(String uid) async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day).toUtc();
      final end = start.add(const Duration(days: 1));
      
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events');
      
      final snap = await col
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final events = snap.docs.map(EventModel.fromDoc).toList();
      
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
        actions: [
          // 同步狀態指示器
          ListenableBuilder(
            listenable: CalendarService.instance,
            builder: (context, child) {
              if (!CalendarService.instance.isSyncing) return const SizedBox.shrink();
              
              return Padding(
                padding: EdgeInsets.only(right: size.width * 0.03),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size.width * 0.04,
                      height: size.width * 0.04,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                      ),
                    ),
                    SizedBox(width: size.width * 0.01),
                    Text(
                      '同步中...',
                      style: TextStyle(
                        fontSize: (12 * responsiveText).clamp(10.0, 14.0),
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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
              
              // Commit Plan Tasks Section
              if (_commitPlanTasks.isNotEmpty) ...[
                _buildCommitPlanSection(constraints, horizontalPadding, titleFontSize),
                SizedBox(height: verticalSpacing * 1.5),
              ],
              
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

                          return ListView.separated(
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

  /// 构建Commit Plan任务section
  Widget _buildCommitPlanSection(BoxConstraints constraints, double horizontalPadding, double titleFontSize) {
    final responsiveText = MediaQuery.textScalerOf(context).scale(1.0);
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalPadding),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.app_registration,
                color: Colors.orange[700],
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'App修正',
                style: TextStyle(
                  fontSize: (14 * responsiveText).clamp(12.0, 16.0),
                  fontWeight: FontWeight.w500,
                  color: Colors.orange[800],
                ),
              ),
            ],
          ),
          
          // Commit Plans List
          ..._commitPlanData.map((data) {
            final commitPlan = data['commitPlan'] as String;
            final event = data['event'] as EventModel;
            
            if (commitPlan.isEmpty) return const SizedBox.shrink();
            
            return GestureDetector(
              onTap: () => _handleAction(event, TaskAction.start),
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                child: Text(
                  commitPlan,
                  style: TextStyle(
                    fontSize: (20 * responsiveText).clamp(13.0, 17.0),
                    color: const Color(0xFF2D3748),
                    height: 1.2,
                  ),
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
