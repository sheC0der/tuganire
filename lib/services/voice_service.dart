import 'package:flutter_tts/flutter_tts.dart';

/// How good the read-aloud voice will be on this device.
enum VoiceQuality { kinyarwanda, swahiliApprox, foreignAccent, unavailable }

/// The app only talks to this interface, so you can later swap in a real
/// Kinyarwanda voice (for example Meta MMS TTS served from your backend)
/// without touching any screen code.
abstract class VoiceService {
  Future<void> init();
  Future<void> speak(String text, {bool slow = false});
  Future<void> stop();
  VoiceQuality get quality;
}

/// Uses the phone's built-in text to speech.
/// Almost no phone ships a Kinyarwanda voice, so it falls back to Swahili,
/// which reads Kinyarwanda spelling reasonably but gets tone and some sounds wrong.
class DeviceVoiceService implements VoiceService {
  final FlutterTts _tts = FlutterTts();
  VoiceQuality _quality = VoiceQuality.unavailable;
  Future<void>? _initFuture;

  @override
  VoiceQuality get quality => _quality;

  @override
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      final raw = await _tts.getLanguages;
      final langs = raw is List ? raw.map((e) => '$e').toList() : <String>[];

      String? find(String prefix) {
        for (final l in langs) {
          if (l.toLowerCase().startsWith(prefix)) return l;
        }
        return null;
      }

      final rw = find('rw');
      final sw = find('sw');
      if (rw != null) {
        await _tts.setLanguage(rw);
        _quality = VoiceQuality.kinyarwanda;
      } else if (sw != null) {
        await _tts.setLanguage(sw);
        _quality = VoiceQuality.swahiliApprox;
      } else {
        _quality = langs.isEmpty ? VoiceQuality.unavailable : VoiceQuality.foreignAccent;
      }
    } catch (_) {
      _quality = VoiceQuality.unavailable;
    }
  }

  @override
  Future<void> speak(String text, {bool slow = false}) async {
    await init();
    if (_quality == VoiceQuality.unavailable || text.trim().isEmpty) return;
    await _tts.stop();
    // 0.5 is roughly normal speed on both Android and iOS.
    await _tts.setSpeechRate(slow ? 0.38 : 0.47);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();
}

String voiceQualityNote(VoiceQuality q) => switch (q) {
      VoiceQuality.kinyarwanda => 'Read aloud uses a Kinyarwanda voice.',
      VoiceQuality.swahiliApprox =>
        'No Kinyarwanda voice on this phone, so a Swahili voice reads aloud. Treat its pronunciation as a rough guide.',
      VoiceQuality.foreignAccent =>
        'No Kinyarwanda or Swahili voice on this phone, so read aloud will sound strongly accented.',
      VoiceQuality.unavailable => 'Read aloud isn’t available on this phone.',
    };
