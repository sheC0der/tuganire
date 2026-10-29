import 'package:supabase_flutter/supabase_flutter.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sign-in state. The app only talks to this interface, so tests can use a fake.
abstract class AuthService {
  bool get isSignedIn;
  String? get email;

  /// Emits true on sign-in and false on sign-out.
  Stream<bool> get signedInChanges;

  /// Throws [AuthFailure] with a message to show the user.
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();

  /// A current access token for the backend, refreshed if it has expired.
  /// Null when signed out or the session can no longer be refreshed.
  /// Throws [AuthFailure] if the sign-in server can't be reached.
  Future<String?> accessToken();
}

/// Email and password sign-in with Supabase. Accounts are created in the
/// Supabase dashboard; the app has no sign-up. supabase_flutter stores the
/// session, so the learner stays signed in across restarts.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth);
  final GoTrueClient _auth;

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  String? get email => _auth.currentUser?.email;

  @override
  Stream<bool> get signedInChanges => _auth.onAuthStateChange.map((s) => s.session != null).distinct();

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthRetryableFetchException {
      throw AuthFailure('Can’t reach the sign-in server. Check your internet connection.');
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'invalid_credentials' => 'Wrong email or password.',
        'email_not_confirmed' => 'This email address hasn’t been confirmed yet.',
        'over_request_rate_limit' => 'Too many attempts. Wait a minute and try again.',
        _ => e.message,
      });
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthException {
      // The local session is cleared even if Supabase can't be reached.
    }
  }

  @override
  Future<String?> accessToken() async {
    var session = _auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      try {
        session = (await _auth.refreshSession()).session;
      } on AuthRetryableFetchException {
        throw AuthFailure('Can’t reach the sign-in server. Check your internet connection.');
      } on AuthException {
        return null;
      }
    }
    return session?.accessToken;
  }
}
