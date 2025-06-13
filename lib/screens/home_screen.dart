import 'package:flutter/material.dart';
import 'package:momentum/providers/chat_provider.dart';
import 'package:momentum/services/proact_coach_service.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  bool _isSyncing = false;
  List<EventModel> _cached = const [];

  Future<void> _sync(BuildContext context) async {
    setState(() => _isSyncing = true);
    final uid = context.read<AuthService>().currentUser!.uid;
    try {
      await CalendarService.instance.syncToday(uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleAction(EventModel e, TaskAction action) async {
    final uid = context.read<AuthService>().currentUser!.uid;
    switch (action) {
      case TaskAction.start:
        await CalendarService.instance.startEvent(uid, e);
        //if (mounted) {
        //  Navigator.of(context).push(
        //    MaterialPageRoute(
        //      builder: (_) => ChatScreen(taskTitle: e.title),
        //    ),
        //  );
        // }
        break;
      case TaskAction.stop:
        await CalendarService.instance.stopEvent(uid, e);
        break;
      case TaskAction.complete:
        await CalendarService.instance.completeEvent(uid, e);
        break;
    }
  }

  Future<void> _testNotification() async {
    try {
      // 首先檢查權限
      final hasPermission = await NotificationService.instance.areNotificationsEnabled();
      print('🔐 通知權限狀態: $hasPermission');
      
      if (!hasPermission) {
        // 請求權限
        final granted = await NotificationService.instance.requestNotificationPermissions();
        print('🔑 權限請求結果: $granted');
        
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('請到設定中開啟通知權限'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      // 先發送一個立即通知
      final immediateSuccess = await NotificationService.instance.showImmediateTestNotification();
      print('📱 立即通知結果: $immediateSuccess');

      // 然後發送5秒延遲通知
      final delayedSuccess = await NotificationService.instance.showTestNotification();
      print('⏰ 延遲通知結果: $delayedSuccess');

      if (mounted) {
        if (immediateSuccess || delayedSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('通知已發送！請檢查通知中心。5秒後還會有第二個通知。'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('通知發送失敗，請檢查控制台日誌'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ 通知測試錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('通知失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final googleAccount = AuthService.instance.googleAccount;
      if (googleAccount == null) {
        // 只 sign out，不要用 Navigator 跳頁
        await AuthService.instance.signOut();
        // AuthGate 會自動顯示 SignInScreen
      } else {
        _sync(context);
      }
    });
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
                child: stream == null
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
                    // 測試通知按鈕
                    Expanded(
                      child: Container(
                        height: buttonHeight,
                        margin: EdgeInsets.only(left: size.width * 0.02),
                        child: ElevatedButton(
                          onPressed: _testNotification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF98E5EE), // Light cyan
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(size.width * 0.06),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_outlined,
                                size: (16 * responsiveText).clamp(14.0, 20.0),
                                color: Colors.black87,
                              ),
                              SizedBox(width: size.width * 0.01),
                              Text('測試通知',
                                  style: TextStyle(
                                      fontSize: (14 * responsiveText).clamp(12.0, 18.0),
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
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

      // Sync button in bottom-right corner
      floatingActionButton: SizedBox(
        width: size.width * 0.14, // Responsive size based on screen width
        height: size.width * 0.14,
        child: FloatingActionButton(
          onPressed: () => _sync(context),
          backgroundColor: const Color(0xFF98E5EE), // Light cyan
          elevation: 2,
          child: _isSyncing
              ? SizedBox(
                  width: size.width * 0.06,
                  height: size.width * 0.06,
                  child: const CircularProgressIndicator(color: Colors.black54))
              : Icon(Icons.sync,
                  color: Colors.black54, size: size.width * 0.07),
        ),
      ),
    );
  }
}
