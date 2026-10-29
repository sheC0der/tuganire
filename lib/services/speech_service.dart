import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech to text using the phone's built-in recogniser.
///
/// Kinyarwanda support depends on the device. Many phones don't offer it,
/// so the app falls back to listening in English and the tutor translates.
class SpeechService {
  final SpeechToText _stt = SpeechToText();

  final ValueNotifier<bool> listening = ValueNotifier(false);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  bool _ready = false;
  String? kinyarwandaLocaleId;
  String englishLocaleId = 'en_US';

  bool get isReady => _ready;
  bool get supportsKinyarwanda => kinyarwandaLocaleId != null;

  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onStatus: (s) => listening.value = s == SpeechToText.listeningStatus,
        onError: (e) {
          listening.value = false;
          lastError.value = _friendlyError(e.errorMsg);
        },
      );
    } catch (_) {
      _ready = false;
    }
    if (_ready) {
      final locales = await _stt.locales();
      for (final l in locales) {
        final id = l.localeId.toLowerCase();
        if (id.startsWith('rw')) kinyarwandaLocaleId = l.localeId;
      }
      final en = locales.where((l) => l.localeId.toLowerCase().startsWith('en'));
      if (en.isNotEmpty) englishLocaleId = en.first.localeId;
    }
    return _ready;
  }

  Future<void> listen({
    required bool kinyarwanda,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    lastError.value = null;
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: kinyarwanda && kinyarwandaLocaleId != null ? kinyarwandaLocaleId : englishLocaleId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stop() => _stt.stop();

  String _friendlyError(String code) => switch (code) {
        'error_no_match' || 'error_speech_timeout' => 'I didn’t catch that. Tap the mic and try again.',
        'error_permission' => 'Microphone permission is off. Turn it on in your phone settings.',
        'error_network' || 'error_network_timeout' => 'Speech recognition needs internet. Check your connection.',
        'error_language_not_supported' || 'error_language_unavailable' =>
          'This phone can’t recognise that language. Switch the mic to English.',
        _ => 'Speech recognition stopped. Try again or type instead.',
      };
}
