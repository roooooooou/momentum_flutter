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

    // IMPORTANT:  initialise Calendar API as soon as we have the account
    await CalendarService.instance.init(googleUser);

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential?> signInSilently() async {
    // A. 先看 Firebase 自己是否已經有使用者
    if (_auth.currentUser != null) {
      return null; // 已登入就不處理
    }

    // B. 使用 google_sign_in 靜默取得帳號（cookie / storage 裏若有）
    final googleAccount = await _googleSignIn.signInSilently();
    if (googleAccount == null) return null; // 沒找到  視為未登入

    // C. 初始化 CalendarService（之後才能 sync）
    await CalendarService.instance.init(googleAccount);

    // D. 取 accessToken / idToken，換 Firebase Credential
    final auth = await googleAccount.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );

    return _auth.signInWithCredential(credential);
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
