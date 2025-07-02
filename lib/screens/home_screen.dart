import 'package:flutter/material.dart';
import 'package:momentum/providers/chat_provider.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/calendar_service.dart';
import '../providers/events_provider.dart';
import '../models/event_model.dart';
import '../widgets/event_card.dart';
import '../screens/chat_screen.dart';
import '../screens/sign_in_screen.dart';
import '../services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../navigation_service.dart';

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
          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('startTime', isLessThan: Timestamp.fromDate(end))
          .orderBy('startTime')
          .get();
      
      final events = snap.docs.map(EventModel.fromDoc).toList();
      
      // 過濾出未開始的事件
      final futureEvents = events.where((event) => 
        event.startTime.isAfter(now) && !event.isDone
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

  @override
  Widget build(BuildContext context) {
    final stream = context.watch<EventsProvider>().stream;
    final size = MediaQuery.of(context).size;
    final responsiveText = MediaQuery.of(context).textScaleFactor;

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
                                onOpenChat: () {
                                  if (mounted) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChangeNotifierProvider(
                                          create: (_) => ChatProvider(
                                              taskTitle: list[i].title,
                                              startTime: list[i].startTime),
                                          child: ChatScreen(
                                              taskTitle: list[i].title),
                                        ),
                                      ),
                                    );
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
                    // Debug 模式按鈕
                    if (const bool.fromEnvironment('dart.vm.product') == false)
                      Row(
                        children: [
                          // 測試通知按鈕
                          Expanded(
                            child: Container(
                              height: buttonHeight,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final success = await NotificationService.instance.showTestNotification();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(success ? '測試通知已排程' : '測試通知失敗'),
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE8D5C4), // Light orange
                                  foregroundColor: Colors.black87,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(size.width * 0.06),
                                  ),
                                ),
                                child: Text('測試通知',
                                    style: TextStyle(
                                        fontSize: (14 * responsiveText).clamp(12.0, 18.0),
                                        fontWeight: FontWeight.w500)),
                              ),
                            ),
                          ),
                          SizedBox(width: size.width * 0.02),
                          // 檢查通知排程按鈕
                          Expanded(
                            child: Container(
                              height: buttonHeight,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final uid = context.read<AuthService>().currentUser?.uid;
                                  if (uid != null) {
                                    try {
                                      final now = DateTime.now();
                                      final start = DateTime(now.year, now.month, now.day).toUtc();
                                      final end = start.add(const Duration(days: 1));
                                      
                                      final col = FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(uid)
                                          .collection('events');
                                      
                                      final snap = await col
                                          .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
                                          .where('startTime', isLessThan: Timestamp.fromDate(end))
                                          .orderBy('startTime')
                                          .get();
                                      
                                      final events = snap.docs.map(EventModel.fromDoc).toList();
                                      
                                      await NotificationScheduler().sync(events);
                                      
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('通知排程檢查完成，處理了 ${events.length} 個事件'),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('通知排程檢查失敗: $e'),
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD4E6F1), // Light blue
                                  foregroundColor: Colors.black87,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(size.width * 0.06),
                                  ),
                                ),
                                child: Text('檢查通知',
                                    style: TextStyle(
                                        fontSize: (14 * responsiveText).clamp(12.0, 18.0),
                                        fontWeight: FontWeight.w500)),
                              ),
                            ),
                          ),
                        ],
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
