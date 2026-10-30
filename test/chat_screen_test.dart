import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:tuganire/controllers/conversation_controller.dart';
import 'package:tuganire/models/scenario.dart';
import 'package:tuganire/screens/chat_screen.dart';
import 'package:tuganire/services/speech_service.dart';
import 'package:tuganire/services/tutor_service.dart';
import 'package:tuganire/services/voice_service.dart';

class _SilentVoice implements VoiceService {
  @override
  VoiceQuality get quality => VoiceQuality.kinyarwanda;
  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text, {bool slow = false}) async {}
  @override
  Future<void> stop() async {}
  @override
  VoiceInfo? get voice => null;
  @override
  Stream<String> get problems => const Stream.empty();
  @override
  final ValueNotifier<String?> preparing = ValueNotifier(null);
}

Future<_SilentVoice> _pumpChat(WidgetTester tester, Size screen) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final voice = _SilentVoice();
  final tutor = TutorService(
    baseUrl: 'https://tutor.example',
    accessToken: () async => 'token',
    onUnauthorized: () async {},
    client: MockClient((_) async => http.Response(
        jsonEncode({
          'reply_rw': 'Mwaramutse! Witwa nde?',
          'reply_en': 'Good morning! What is your name?',
          'suggestions': [],
        }),
        200)),
  );

  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<SpeechService>(create: (_) => SpeechService()),
      Provider<VoiceService>.value(value: voice),
    ],
    child: MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) =>
            ConversationController(tutor: tutor, voice: voice, level: Level.beginner, scenario: scenarios.first)
              ..start(),
        child: const ChatScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Mwaramutse! Witwa nde?'), findsOneWidget);
  return voice;
}

void main() {
  testWidgets('on wide screens the conversation and composer sit in a centred 720px column', (tester) async {
    await _pumpChat(tester, const Size(1400, 900));

    for (final finder in [find.byType(ListView), find.byType(TextField).last]) {
      final rect = tester.getRect(finder);
      expect(rect.width, lessThanOrEqualTo(720));
      expect(rect.center.dx, closeTo(700, 1), reason: 'centred');
    }
    expect(tester.getRect(find.byType(ListView)).width, 720);
  });

  testWidgets('on phones the conversation uses the full width as before', (tester) async {
    await _pumpChat(tester, const Size(400, 800));

    expect(tester.getRect(find.byType(ListView)).width, 400);
  });

  testWidgets('"Hear again" shows a spinner while that message’s audio is generated', (tester) async {
    final voice = await _pumpChat(tester, const Size(400, 800));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    voice.preparing.value = 'Mwaramutse! Witwa nde?';
    await tester.pump();
    expect(
        find.descendant(
            of: find.widgetWithText(TextButton, 'Hear again'), matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);

    voice.preparing.value = null;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
