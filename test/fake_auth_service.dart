import 'dart:async';

import 'package:tuganire/services/auth_service.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({this.signedIn = false, this.password = 'secret'});

  final String password;
  final _changes = StreamController<bool>.broadcast();
  bool signedIn;
  String? token = 'token-123';
  int signOutCalls = 0;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get email => signedIn ? 'learner@example.com' : null;

  @override
  Stream<bool> get signedInChanges => _changes.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (password != this.password) throw AuthFailure('Wrong email or password.');
    signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    signedIn = false;
    _changes.add(false);
  }

  @override
  Future<String?> accessToken() async => signedIn ? token : null;
}
