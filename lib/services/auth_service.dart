import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A thin wrapper around FirebaseAuth + Google Sign‑In.
/// Exposes: [signInWithGoogle], [signOut], and a convenient [authStateChanges] stream.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/tasks',
    ],
  );

  /// Stream of [User?] that emits on every auth state change.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;
  //String? _cachedAccessToken;

  /// Signs the user in with Google and returns the resulting [UserCredential].
  /// Throws if the flow is aborted or fails.
  Future<UserCredential> signInWithGoogle() async {
    // Trigger the Google authentication flow.
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'ERROR_ABORTED_BY_USER',
        message: 'Sign in aborted by user',
      );
    }

    // Obtain the auth details from the request.
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    //_cachedAccessToken = googleAuth.accessToken;
    // Create a new credential for Firebase.
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Sign in to Firebase with the credential.
    return await _auth.signInWithCredential(credential);
  }

  /// Signs the current user out from both Firebase and Google.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<String?> getAccessToken() async {
    final googleUser = await _googleSignIn.signInSilently();
    final auth = await googleUser?.authentication;
    return auth?.accessToken;
  }
}
