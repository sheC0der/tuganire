import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'screens/setup_screen.dart';
import 'services/speech_service.dart';
import 'services/tutor_service.dart';
import 'services/voice_service.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TuganireApp());
}

class TuganireApp extends StatelessWidget {
  const TuganireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<TutorService>(
          create: (_) => TutorService(baseUrl: AppConfig.backendUrl, appToken: AppConfig.appToken),
        ),
        Provider<SpeechService>(create: (_) => SpeechService()),
        Provider<VoiceService>(create: (_) => DeviceVoiceService()..init()),
      ],
      child: MaterialApp(
        title: 'Tuganire',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const SetupScreen(),
      ),
    );
  }
}
