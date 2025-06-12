import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/calendar_service.dart';

/// Wraps FirebaseAuth + Google Sign‑In with Calendar scope.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      // Calendar read / write
      'https://www.googleapis.com/auth/calendar.events',
    ],
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  GoogleSignInAccount? get googleAccount => _googleSignIn.currentUser;

  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'ERROR_ABORTED_BY_USER',
        message: 'Sign-in aborted by user',
      );
    }

    // IMPORTANT: 尝试初始化Calendar API，但不要让错误阻止登录
    try {
      await CalendarService.instance.init(googleUser);
    } catch (e) {
      print('Calendar initialization failed: $e');
      // 不抛出错误，继续登录流程
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signInSilently() async {
    // 1. 先試著拿 Google 帳號（記憶體或 cookie 裡）
    final googleAccount =
        _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();

    if (googleAccount == null) return; // 沒帳號 → 視為未登入
    
    // 尝试初始化Calendar，但不要让错误阻止登录
    try {
      await CalendarService.instance.init(googleAccount); // **** 關鍵 ****
    } catch (e) {
      print('Calendar initialization failed in signInSilently: $e');
    }

    // 2. Firebase 可能已經有 user，就不用再 sign-in
    if (_auth.currentUser == null) {
      final auth = await googleAccount.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await _auth.signInWithCredential(cred);
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<String?> getAccessToken() async {
    final user = await _googleSignIn.signInSilently();
    final auth = await user?.authentication;
    return auth?.accessToken;
  }
}
