// =============================================================================
// services/auth_service.dart — Firebase Authentication + Google Sign-In
// =============================================================================
//
// PURPOSE:
//   Handles everything auth-related. Login, logout, session persistence,
//   and providing the Firebase UID that becomes each user's unique memory key.
//
// HOW IT WORKS:
//   1. User taps "Continue with Google"
//   2. Google OAuth sheet opens (native Android bottom sheet)
//   3. User picks their Google account
//   4. We get a GoogleSignInAccount → exchange for Firebase credential
//   5. Firebase signs in → we get a User object with a permanent uid
//   6. That uid is sent to the backend as user_id on every request
//   7. Firebase persists the session — user stays logged in across restarts
//
// WHY FIREBASE UID AS USER_ID:
//   - Permanent: same uid forever, even if they reinstall
//   - Unique: guaranteed globally unique by Firebase
//   - Secure: backend can verify it with Firebase Admin SDK later
//   - Isolated: each uid gets its own SQLite facts + ChromaDB collection
//
// USAGE:
//   final user = await AuthService.signInWithGoogle();
//   final uid = AuthService.currentUserId;   // use this as user_id everywhere
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // ── Current user accessors ─────────────────────────────────────────────

  /// The currently signed-in Firebase user, or null if not logged in.
  static User? get currentUser => _auth.currentUser;

  /// The Firebase UID — this is what we send to the backend as user_id.
  /// Guaranteed unique per Google account. Permanent.
  static String? get currentUserId => _auth.currentUser?.uid;

  /// Display name from Google profile.
  static String? get currentUserName => _auth.currentUser?.displayName;

  /// Email from Google profile.
  static String? get currentUserEmail => _auth.currentUser?.email;

  /// Photo URL from Google profile (for future avatar display).
  static String? get currentUserPhoto => _auth.currentUser?.photoURL;

  /// Stream of auth state changes — listen to this to react to login/logout.
  /// Emits: User (logged in) or null (logged out).
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Sign In ────────────────────────────────────────────────────────────

  /// Triggers the Google Sign-In flow and signs into Firebase.
  ///
  /// Returns the Firebase User on success.
  /// Returns null if user cancelled.
  /// Throws [AuthException] on error.
  static Future<User?> signInWithGoogle() async {
    try {
      // 1. Trigger Google account picker (native Android sheet)
      final GoogleSignInAccount? googleAccount = await _googleSignIn.signIn();

      // User cancelled the picker
      if (googleAccount == null) return null;

      // 2. Get auth tokens from Google
      final GoogleSignInAuthentication googleAuth =
          await googleAccount.authentication;

      // 3. Create Firebase credential from Google tokens
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Sign into Firebase with the credential
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_firebaseErrorMessage(e.code));
    } catch (e) {
      throw AuthException('Sign in failed. Please try again.');
    }
  }

  // ── Sign Out ───────────────────────────────────────────────────────────

  /// Signs out from both Firebase and Google.
  /// Clears session completely — next open shows login screen.
  static Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  // ── Session check ──────────────────────────────────────────────────────

  /// True if a user is currently signed in.
  static bool get isSignedIn => _auth.currentUser != null;

  /// Gets a fresh Firebase ID token for the current user.
  /// The backend verifies this token before accepting any pair-scoped requests.
  static Future<String?> getIdToken() async {
    return await _auth.currentUser?.getIdToken();
  }

  // ── Error messages ─────────────────────────────────────────────────────

  static String _firebaseErrorMessage(String code) {
    switch (code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return 'Sign in failed. Please try again.';
    }
  }
}

// ---------------------------------------------------------------------------
// Custom exception
// ---------------------------------------------------------------------------

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
