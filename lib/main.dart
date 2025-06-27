import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'providers/events_provider.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/notification_service.dart';
import 'navigation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.initialize();
  await AuthService.instance.signInSilently();

  runApp(const ProcrastinationControlApp());
}

class ProcrastinationControlApp extends StatefulWidget {
  const ProcrastinationControlApp({super.key});

  @override
  State<ProcrastinationControlApp> createState() => _ProcrastinationControlAppState();
}

class _ProcrastinationControlAppState extends State<ProcrastinationControlApp> with WidgetsBindingObserver {
  DateTime? _lastActiveDate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastActiveDate = DateTime.now();
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
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // 檢查是否跨日了
      if (_lastActiveDate != null) {
        final lastDate = DateTime(_lastActiveDate!.year, _lastActiveDate!.month, _lastActiveDate!.day);
        if (!today.isAtSameMomentAs(lastDate)) {
          // 跨日了，通知所有相關 provider 刷新
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final context = NavigationService.navigatorKey.currentContext;
              if (context != null) {
                try {
                  final authService = context.read<AuthService>();
                  final eventsProvider = context.read<EventsProvider>();
                  eventsProvider.refreshToday(authService.currentUser);
                } catch (e) {
                  // 如果 context 不可用，忽略錯誤
                }
              }
            }
          });
        }
      }
      
      _lastActiveDate = now;
    } else if (state == AppLifecycleState.paused) {
      _lastActiveDate = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: AuthService.instance),
        ChangeNotifierProxyProvider<AuthService, EventsProvider>(
          create: (_) => EventsProvider(),
          update: (_, auth, provider) => provider!..setUser(auth.currentUser),
        ),
      ],
      child: MaterialApp(
        title: 'Procrastination-Calendar',
        theme: AppTheme.light(),
        navigatorKey: NavigationService.navigatorKey,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _triedSilent = false; // 記錄是否補過一次

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<User?>(
      stream: auth.authStateChanges,
      builder: (_, snap) {
        // (a) Firebase 還在把 IndexedDB 的 session 撈回來
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // (b) 已經登入 → 進 Home
        if (snap.hasData) {
          return const HomeScreen();
        }

        // (c) 還沒登入，而且還沒補過 silent → 下一個 frame 補一次
        if (!_triedSilent) {
          _triedSilent = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => auth.signInSilently(),
          );
        }

        // (d) 顯示登入畫面
        return const SignInScreen();
      },
    );
  }
}
