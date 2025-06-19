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
      print('Current user: ${AuthService.instance.currentUser}');
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
        CalendarService.instance.resumeSync(uid).catchError((e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Resume sync failed: $e')));
          }
        });
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
          if (CalendarService.instance.isSyncing)
            Padding(
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
                                              taskTitle: list[i].title),
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
                child: Row(
                  children: [
                    // Daily Report 按鈕
                    Expanded(
                      child: Container(
                        height: buttonHeight,
                        margin: EdgeInsets.only(right: size.width * 0.02),
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
                    ),
                    // 測試通知按鈕 (Debug 模式)
                    if (const bool.fromEnvironment('dart.vm.product') == false)
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
