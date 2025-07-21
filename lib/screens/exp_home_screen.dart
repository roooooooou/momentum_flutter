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
import '../services/data_path_service.dart';
import '../services/experiment_config_service.dart';

class ExpHomeScreen extends StatefulWidget {
  const ExpHomeScreen({super.key});

  /// 静态方法：重新整理commit plans显示
  static Future<void> refreshCommitPlans(BuildContext context, String uid) async {
    final state = context.findAncestorStateOfType<_ExpHomeScreenState>();
    if (state != null) {
      await state._loadCommitPlanTasks(uid);
    }
  }

  /// 靜態方法：強制刷新commit plans（用於從聊天頁面返回時）
  static Future<void> forceRefreshCommitPlans(BuildContext context, String uid) async {
    final state = context.findAncestorStateOfType<_ExpHomeScreenState>();
    if (state != null) {
      // 重置節流時間，強制刷新
      state._lastCommitPlanLoadTime = null;
      await state._loadCommitPlanTasks(uid);
    }
  }

  @override
  State<ExpHomeScreen> createState() => _ExpHomeScreenState();
}

class _ExpHomeScreenState extends State<ExpHomeScreen> with WidgetsBindingObserver {
  List<EventModel> _todayEvents = [];
  final Set<String> _shownDialogTaskIds = {};
  bool _isLoadingCommitPlans = false;
  List<EventModel> _commitPlanTasks = [];
  List<Map<String, dynamic>> _commitPlanData = [];
  
  // 添加缺失的变量
  bool _isInitialSync = true;
  DateTime? _lastCommitPlanLoadTime;
  List<EventModel>? _cached;

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
          if (kDebugMode) {
            print('ExpHomeScreen: 开始初始同步，uid: $uid');
          }
          await CalendarService.instance.syncToday(uid);
          if (kDebugMode) {
            print('ExpHomeScreen: 同步完成，开始加载commit plan任务');
          }
          // 載入有commit plan的任務
          await _loadCommitPlanTasks(uid);
        } catch (e) {
          if (kDebugMode) {
            print('ExpHomeScreen: 同步失败: $e');
          }
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
        if (kDebugMode) {
          print('ExpHomeScreen: App resumed，开始刷新数据，uid: $uid');
        }
        
        // 強制刷新事件提供者以更新日期範圍（處理跨日情況）
        context.read<EventsProvider>().refreshToday(context.read<AuthService>().currentUser!);
        
        // 執行日曆同步
        CalendarService.instance.resumeSync(uid).catchError((e) {
          if (kDebugMode) {
            print('ExpHomeScreen: Resume sync failed: $e');
          }
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
          if (kDebugMode) {
            print('ExpHomeScreen: 重新加载commit plan任务');
          }
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
      // 修复时区问题：使用台湾时区计算今天的范围
      final now = DateTime.now();
      final localToday = DateTime(now.year, now.month, now.day); // 本地午夜
      final localTomorrow = localToday.add(const Duration(days: 1)); // 本地明天午夜
      
      // 转换为UTC用于Firestore查询
      final start = localToday.toUtc();
      final end = localTomorrow.toUtc();
      
      if (kDebugMode) {
        print('_loadCommitPlanTasks: 本地时间范围 ${localToday.toString()} 到 ${localTomorrow.toString()}');
        print('_loadCommitPlanTasks: UTC查询时间范围 ${start.toString()} 到 ${end.toString()}');
      }
      
      // 使用 DataPathService 获取正确的 events 集合
      final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
      
      final snap = await eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final allEvents = snap.docs.map(EventModel.fromDoc).toList();
      final events = allEvents.where((event) => event.isActive).toList();
      
      final List<Map<String, dynamic>> commitPlanData = [];
      
      // 檢查每個未完成的事件是否有commit plan
      for (final event in events) {
        if (event.isDone || !event.isActive) continue;
        
        // 使用 DataPathService 获取正确的 chats 集合
        final chatsCollection = await DataPathService.instance.getUserEventChatsCollection(uid, event.id);
        final chatsSnap = await chatsCollection
            .where('commit_plan', isNotEqualTo: '')
            .where('commit_plan', isNotEqualTo: null)
            .get();
            
        // 在内存中排序并获取最新的记录
        final chatDocs = chatsSnap.docs;
        if (chatDocs.isNotEmpty) {
          chatDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = (aData['start_time'] as Timestamp?)?.toDate();
            final bTime = (bData['start_time'] as Timestamp?)?.toDate();
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime); // 降序排序
          });
        
          // 使用排序后的第一条记录
          final chatDoc = chatDocs.first;
          final chatData = chatDoc.data() as Map<String, dynamic>;
          final commitPlan = chatData['commit_plan'] as String? ?? ''; // commit plan文本字段
          
          // 只有commit plan文本不为空时才添加到列表中
          if (commitPlan.isNotEmpty) {
            commitPlanData.add({
              'event': event,
              'commitPlan': commitPlan,
              'chatId': chatDoc.id,
            });
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _commitPlanTasks = commitPlanData.map((data) => data['event'] as EventModel).toList();
          _commitPlanData = commitPlanData; // 儲存完整的commit plan資料
        });
      }
      
      if (kDebugMode) {
        print('_loadCommitPlanTasks: 找到 ${commitPlanData.length} 个有commit plan的任务');
      }
    } catch (e) {
      debugPrint('加载commit plan任务失败: $e');
      if (kDebugMode) {
        print('_loadCommitPlanTasks 错误详情: $e');
      }
    } finally {
      _isLoadingCommitPlans = false; // 重置載入狀態
    }
  }

  /// 检查是否有任务需要显示开始对话框（App Resume时调用）
  Future<void> _checkPendingTaskStart(String uid) async {
    try {
      // 修复时区问题：使用台湾时区计算今天的范围
      final now = DateTime.now();
      final localToday = DateTime(now.year, now.month, now.day); // 本地午夜
      final localTomorrow = localToday.add(const Duration(days: 1)); // 本地明天午夜
      
      // 转换为UTC用于Firestore查询
      final start = localToday.toUtc();
      final end = localTomorrow.toUtc();
      
      // 使用DataPathService获取正确的events集合
      final eventsCollection = await DataPathService.instance.getUserEventsCollection(uid);
      
      final snap = await eventsCollection
          .where('scheduledStartTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('scheduledStartTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('scheduledStartTime')
          .get();
      
      final events = snap.docs.map(EventModel.fromDoc).where((event) => event.isActive).toList();
      
      // 找到应该开始但还没开始的任务
      final pendingEvents = events.where((event) {
        if (event.isDone || event.actualStartTime != null) return false;
        if (_shownDialogTaskIds.contains(event.id)) return false;
        if (NotificationHandler.instance.shownCompletionDialogTaskIds.contains(event.id)) return false;
        
        // 只在任务开始时间前后20分钟内显示对话框
        final bufferTime = const Duration(minutes: 20);
        final latestShowTime = event.scheduledStartTime.add(bufferTime);
        
        return now.isAfter(event.scheduledStartTime) && now.isBefore(latestShowTime);
      }).toList();
      
      if (pendingEvents.isNotEmpty) {
        // 显示开始对话框
        final event = pendingEvents.first;
        _showTaskStartDialog(event);
        _shownDialogTaskIds.add(event.id);
      }
    } catch (e) {
      if (kDebugMode) {
        print('检查待开始任务失败: $e');
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

  /// 显示任务开始对话框
  void _showTaskStartDialog(EventModel event) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => TaskStartDialog(
        event: event,
      ),
    );
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
            Text("app_config = 1",
                style: TextStyle(
                    fontSize: (16 * responsiveText).clamp(14.0, 20.0),
                    color: Colors.deepPurple,
                    fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          // 测试每日报告通知检查按钮（仅在debug模式显示）
          if (kDebugMode)
            IconButton(
              onPressed: () async {
                try {
                  await NotificationService.instance.testDailyReportCheck();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('每日报告检查测试完成，请查看控制台输出'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('测试失败: $e')),
                    );
                  }
                }
              },
              icon: Icon(Icons.assignment, size: iconSize),
              tooltip: '测试每日报告检查',
            ),
          
          // 修复无限循环按钮（仅在debug模式显示）
          if (kDebugMode)
            IconButton(
              onPressed: () async {
                final uid = context.read<AuthService>().currentUser?.uid;
                if (uid != null) {
                  try {
                    await ExperimentConfigService.instance.fixInfiniteLoop(uid);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('无限循环问题修复完成'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('修复失败: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              icon: Icon(Icons.bug_report, size: iconSize),
              tooltip: '修复无限循环',
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
                          final list = _cached ?? [];
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
                                                      taskDescription: list[i].description,
                                                      startTime: list[i].scheduledStartTime,
                                                      uid: uid,
                                                      eventId: list[i].id,
                                                      chatId: chatId,
                                                      entryMethod: ChatEntryMethod.eventCard,
                                                    ),
                                                    child: ChatScreen(
                                                      taskTitle: list[i].title,
                                                      taskDescription: list[i].description,
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
                                      color: Colors.white, // 不透明的白色背景
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

  /// 构建Commit Plan任务section
  Widget _buildCommitPlanSection(BoxConstraints constraints, double horizontalPadding, double titleFontSize) {
    final responsiveText = MediaQuery.textScalerOf(context).scale(1.0);
    
    if (kDebugMode) {
      print('ExpHomeScreen UI: _commitPlanTasks.length = ${_commitPlanTasks.length}');
      print('ExpHomeScreen UI: _commitPlanData.length = ${_commitPlanData.length}');
      print('_buildCommitPlanSection: 构建commit plan section，数据长度: ${_commitPlanData.length}');
    }
    
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
                'Commit Plan',
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
            
            if (kDebugMode) {
              print('_buildCommitPlanSection: 渲染事件 ${event.title} 的commit plan: "$commitPlan"');
            }
            
            if (commitPlan.isEmpty) {
              if (kDebugMode) {
                print('_buildCommitPlanSection: 跳过空commit plan的事件 ${event.title}');
              }
              return const SizedBox.shrink();
            }
            
            return GestureDetector(
              onTap: () => _handleAction(event, TaskAction.start),
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 任务名称
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: (16 * responsiveText).clamp(14.0, 18.0),
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Commit Plan内容
                    Text(
                      commitPlan,
                      style: TextStyle(
                        fontSize: (14 * responsiveText).clamp(12.0, 16.0),
                        color: const Color(0xFF2D3748),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
} 