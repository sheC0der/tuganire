import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/scenario.dart';
import '../services/tutor_service.dart';
import '../services/voice_service.dart';

/// Holds one conversation: the messages, whether the tutor is thinking,
/// and the learner's display settings.
class ConversationController extends ChangeNotifier {
  ConversationController({
    required this.tutor,
    required this.voice,
    required this.level,
    required this.scenario,
  }) {
    _voiceProblems = voice.problems.listen((message) {
      voiceProblem = message;
      _notify();
    });
    voice.preparing.addListener(_notify);
  }

  final TutorService tutor;
  final VoiceService voice;
  final Level level;
  final Scenario scenario;

  final List<ChatMessage> messages = [];
  bool isThinking = false;
  String? error;
  bool showTranslations = true;
  bool readAloud = true;

  /// Why read aloud just failed to play. The screen shows it once via [takeVoiceProblem].
  String? voiceProblem;

  /// The text whose audio is still being generated, so its button can show it's loading.
  String? get preparingSpeech => voice.preparing.value;

  bool _disposed = false;
  late final StreamSubscription<String> _voiceProblems;

  /// The tutor opens the conversation.
  Future<void> start() => _requestTutorTurn();

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || isThinking) return;
    await voice.stop();
    messages.add(ChatMessage.learner(t));
    _notify();
    await _requestTutorTurn();
  }

  /// Retries the last failed request. The learner's message is kept.
  Future<void> retry() => _requestTutorTurn();

  void speak(String text) => voice.speak(text, slow: level == Level.beginner);

  String? takeVoiceProblem() {
    final problem = voiceProblem;
    voiceProblem = null;
    return problem;
  }

  void toggleTranslations() {
    showTranslations = !showTranslations;
    _notify();
  }

  void toggleReadAloud() {
    readAloud = !readAloud;
    if (!readAloud) voice.stop();
    _notify();
  }

  Future<void> _requestTutorTurn() async {
    if (isThinking) return;
    isThinking = true;
    error = null;
    _notify();
    try {
      final reply = await tutor.nextTurn(
        level: level,
        scenarioId: scenario.id,
        history: messages,
      );
      if (_disposed) return;
      if (messages.isNotEmpty && messages.last.speaker == Speaker.learner) {
        messages.last.feedback = reply.feedback;
      }
      messages.add(ChatMessage.tutor(
        reply.replyRw,
        translation: reply.replyEn,
        suggestions: reply.suggestions,
      ));
      if (readAloud) speak(reply.replyRw);
    } on TutorException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'The tutor couldn’t reply. Try again.';
    } finally {
      isThinking = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _voiceProblems.cancel();
    voice.preparing.removeListener(_notify);
    voice.stop();
    super.dispose();
  }
}
