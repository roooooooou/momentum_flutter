import 'package:flutter/material.dart';
import 'package:momentum/providers/chat_provider.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../providers/events_provider.dart';
import '../models/event_model.dart';
import '../models/enums.dart';
import '../widgets/event_card.dart';
import '../screens/chat_screen.dart';
import '../services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<EventModel> _cached = const [];
  bool _isInitialSync = true;

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

  Future<void> _handleAction(EventModel e, TaskAction action) async {
    final uid = context.read<AuthService>().currentUser!.uid;
    switch (action) {
      case TaskAction.start:
        await CalendarService.instance.startEvent(uid, e);
        break;
      case TaskAction.stop:
        await CalendarService.instance.stopEvent(uid, e);
        break;
      case TaskAction.complete:
        await CalendarService.instance.completeEvent(uid, e);
        break;
    }
  }

  /// 🧪 測試每日數據聚合功能
  Future<void> _testDailyMetrics() async {
    bool dialogShown = false;
    try {
      final uid = context.read<AuthService>().currentUser?.uid;
      if (uid == null) {
        _showError('用戶未登入');
        return;
      }

      if (kDebugMode) {
        print('開始測試每日數據聚合，UID: $uid');
      }

      // 顯示加載對話框
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在處理數據聚合...'),
            ],
          ),
        ),
      );
      dialogShown = true;

      if (kDebugMode) {
        print('調用 Cloud Function: manual_daily_metrics');
      }

      // 調用Cloud Function
      final result = await FirebaseFunctions.instance
          .httpsCallable('manual_daily_metrics')
          .call({
        'uid': uid,
        // 可以指定日期，例如：'date': '2025-07-06'
      });

      if (kDebugMode) {
        print('Cloud Function 調用成功，結果: ${result.data}');
      }

      // 關閉加載對話框
      if (mounted && dialogShown) {
        Navigator.of(context).pop();
        dialogShown = false;
        
        // 檢查結果
        final data = result.data;
        if (data != null && data['success'] == true) {
          final metrics = data['metrics'];
          if (metrics != null) {
            // 安全地轉換類型
            final safeMetrics = Map<String, dynamic>.from(metrics as Map);
            _showResults(safeMetrics);
          } else {
            _showError('返回數據格式錯誤：缺少 metrics');
          }
        } else {
          final errorMsg = data?['error'] ?? '未知錯誤';
          _showError('處理失敗: $errorMsg');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('測試每日數據聚合失敗: $e');
        print('Stack trace: $stackTrace');
      }
      
      // 確保關閉加載對話框
      if (mounted && dialogShown) {
        try {
          Navigator.of(context).pop();
        } catch (popError) {
          if (kDebugMode) {
            print('關閉對話框失敗: $popError');
          }
        }
      }
      
      // 顯示詳細錯誤信息
      String errorMessage = '測試失敗: $e';
      if (e.toString().contains('firebase_functions/not-found')) {
        errorMessage = '錯誤：找不到 Cloud Function (manual_daily_metrics)';
      } else if (e.toString().contains('firebase_functions/permission-denied')) {
        errorMessage = '錯誤：權限被拒絕，請檢查用戶認證';
      } else if (e.toString().contains('firebase_functions/internal')) {
        errorMessage = '錯誤：Cloud Function 內部錯誤';
      }
      
      _showError(errorMessage);
    }
  }

  /// 顯示測試結果
  void _showResults(Map<String, dynamic> metrics) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.green),
            SizedBox(width: 8),
            Text('📊 每日數據聚合結果'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('日期: ${metrics['date'] ?? 'N/A'}', 
                   style: const TextStyle(fontWeight: FontWeight.bold)),
              const Divider(),
              const SizedBox(height: 8),
              _buildMetricRow('📅 事件總數', '${metrics['event_total_count'] ?? 0}'),
              _buildMetricRow('✅ 完成事件', '${metrics['event_complete_count'] ?? 0}'),
              _buildMetricRow('⏰ 過期事件', '${metrics['event_overdue_count'] ?? 0}'),
              _buildMetricRow('📝 未完成事件', '${metrics['event_not_finish_count'] ?? 0}'),
              _buildMetricRow('🤝 承諾計劃', '${metrics['event_commit_plan_count'] ?? 0}'),
              const SizedBox(height: 8),
              _buildMetricRow('💬 聊天總數', '${metrics['chat_total_count'] ?? 0}'),
              _buildMetricRow('🚀 開始決定', '${metrics['chat_start_count'] ?? 0}'),
              _buildMetricRow('⏳ 延後決定', '${metrics['chat_snooze_count'] ?? 0}'),
              _buildMetricRow('👋 直接離開', '${metrics['chat_leave_count'] ?? 0}'),
              const SizedBox(height: 8),
              _buildMetricRow('🔔 通知總數', '${metrics['notif_total_count'] ?? 0}'),
              _buildMetricRow('👆 通知點擊', '${metrics['notif_open_count'] ?? 0}'),
              _buildMetricRow('📱 應用打開', '${metrics['app_open_count'] ?? 0}次'),
              _buildMetricRow('⏱️ 平均使用時間', '${metrics['app_average_open_time'] ?? 0}秒'),
              _buildMetricRow('🔔➜📱 通知觸發打開', '${metrics['app_open_by_notif_count'] ?? 0}次'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  /// 構建指標行
  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 顯示錯誤信息
  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
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
                                              startTime: list[i].scheduledStartTime,
                                              uid: uid,
                                              eventId: list[i].id,
                                              chatId: chatId,
                                              entryMethod: ChatEntryMethod.eventCard, // 🎯 新增：事件卡片進入
                                            ),
                                            child: ChatScreen(
                                                taskTitle: list[i].title),
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
                          // TODO: navigate to Daily Report
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
                    
                    // 🧪 測試每日數據聚合按鈕（臨時用於測試）
                    if (const bool.fromEnvironment('dart.vm.product') == false)
                      Container(
                        width: double.infinity,
                        height: buttonHeight,
                        margin: EdgeInsets.only(bottom: size.height * 0.01),
                        child: ElevatedButton(
                          onPressed: () => _testDailyMetrics(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFE6CC), // Light orange
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(size.width * 0.06),
                            ),
                          ),
                          child: Text('🧪 測試每日數據聚合',
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
