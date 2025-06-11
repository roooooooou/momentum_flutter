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
import 'services/proact_coach_service.dart';
import 'services/fake_llm_service.dart';
import 'providers/chat_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  //await AuthService.instance.signInSilently();

  runApp(const ProcrastinationControlApp());
}

class ProcrastinationControlApp extends StatelessWidget {
  const ProcrastinationControlApp({super.key});

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
