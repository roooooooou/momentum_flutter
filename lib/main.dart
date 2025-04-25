import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'providers/tasks_provider.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProcrastinationControlApp());
}

class ProcrastinationControlApp extends StatelessWidget {
  const ProcrastinationControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: AuthService.instance),
        ChangeNotifierProxyProvider<AuthService, TasksProvider>(
          create: (_) => TasksProvider(),
          update: (_, authService, tasksProvider) =>
              tasksProvider!..setUser(authService.currentUser),
        ),
      ],
      child: MaterialApp(
        title: 'Procrastination Control Control Group',
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    return StreamBuilder<User?>(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.hasData ? const HomeScreen() : const SignInScreen();
      },
    );
  }
}
