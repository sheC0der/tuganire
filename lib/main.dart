import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/setup_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'services/remote_voice_service.dart';
import 'services/speech_service.dart';
import 'services/tutor_service.dart';
import 'services/voice_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.supabaseConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );
  runApp(TuganireApp(auth: SupabaseAuthService(Supabase.instance.client.auth)));
}

class TuganireApp extends StatelessWidget {
  const TuganireApp({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: auth),
        Provider<TutorService>(
          create: (_) => TutorService(
            baseUrl: AppConfig.backendUrl,
            accessToken: auth.accessToken,
            onUnauthorized: auth.signOut,
          ),
        ),
        Provider<SpeechService>(create: (_) => SpeechService()),
        Provider<VoiceService>(
          create: (_) => RemoteVoiceService(
            baseUrl: AppConfig.backendUrl,
            accessToken: auth.accessToken,
            onUnauthorized: auth.signOut,
            fallback: DeviceVoiceService(),
          )..init(),
        ),
      ],
      child: MaterialApp(
        title: 'Tuganire',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const AuthGate(),
      ),
    );
  }
}

/// Shows sign-in or the app depending on the session. On sign-out (including
/// when the backend rejects the token) it closes any open screens first.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _auth = context.read<AuthService>();
  late bool _signedIn = _auth.isSignedIn;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _auth.signedInChanges.listen((signedIn) {
      if (!mounted || signedIn == _signedIn) return;
      if (!signedIn) Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() => _signedIn = signedIn);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _signedIn ? const SetupScreen() : const SignInScreen();
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This build is missing its Supabase settings.\n\n'
              'Build or run it with --dart-define=SUPABASE_URL=... and '
              '--dart-define=SUPABASE_PUBLISHABLE_KEY=... (see README.md).',
            ),
          ),
        ),
      ),
    );
  }
}
