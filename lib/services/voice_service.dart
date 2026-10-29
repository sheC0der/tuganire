import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// How good the read-aloud voice will be on this device.
enum VoiceQuality { kinyarwanda, swahiliApprox, foreignAccent, unavailable }

/// The voice read-aloud uses, for showing the learner (see "Test voice").
class VoiceInfo {
  const VoiceInfo({required this.name, required this.locale, required this.quality, required this.voiceCount});

  /// The voice's name, or a description when the device's default voice is used.
  final String name;
  final String? locale;
  final VoiceQuality quality;

  /// How many voices the device offers.
  final int voiceCount;
}

/// The app only talks to this interface, so you can later swap in a real
/// Kinyarwanda voice (for example Meta MMS TTS served from your backend)
/// without touching any screen code.
abstract class VoiceService {
  Future<void> init();

  /// Reads [text] aloud. Never fails silently: if it can't play, the reason
  /// is sent on [problems] for the screen to show.
  Future<void> speak(String text, {bool slow = false});
  Future<void> stop();
  VoiceQuality get quality;

  /// The chosen voice, or null while none has been found.
  VoiceInfo? get voice;

  /// Messages for the learner when read aloud can't play.
  Stream<String> get problems;
}

/// Picks the read-aloud voice: Kinyarwanda, then Swahili, otherwise null for the
/// device's default voice. Voices are maps with "name" and "locale" (plus
/// "features" on Android), as flutter_tts's getVoices returns them.
@visibleForTesting
({Map<String, String> voice, VoiceQuality quality})? chooseVoice(List<Map<String, String>> voices) {
  // Android lists voices that still need downloading; they can't speak yet.
  final usable = voices.where((v) => !(v['features'] ?? '').contains('notInstalled')).toList();

  Map<String, String>? best(String language) {
    final matches = usable.where((v) {
      final locale = (v['locale'] ?? '').toLowerCase().replaceAll('_', '-');
      return locale == language || locale.startsWith('$language-');
    }).toList();
    if (matches.isEmpty) return null;
    // Edge's online "Natural" voices (e.g. Microsoft Rafiki/Zuri for Swahili) sound far better.
    bool natural(Map<String, String> v) => (v['name'] ?? '').toLowerCase().contains('natural');
    return matches.firstWhere(natural, orElse: () => matches.first);
  }

  final rw = best('rw');
  if (rw != null) return (voice: rw, quality: VoiceQuality.kinyarwanda);
  final sw = best('sw');
  if (sw != null) return (voice: sw, quality: VoiceQuality.swahiliApprox);
  return null;
}

/// Uses the device's built-in text to speech (the browser's speechSynthesis on web).
/// Almost no device ships a Kinyarwanda voice, so it falls back to Swahili,
/// which reads Kinyarwanda spelling reasonably but gets tone and some sounds wrong.
class DeviceVoiceService implements VoiceService {
  DeviceVoiceService({
    FlutterTts? tts,
    @visibleForTesting this.firstWait = const Duration(seconds: 5),
    @visibleForTesting this.retryWait = const Duration(seconds: 1),
    @visibleForTesting this.pollInterval = const Duration(milliseconds: 200),
    @visibleForTesting this.startTimeout = const Duration(seconds: 4),
  }) : _tts = tts ?? FlutterTts() {
    _tts.setStartHandler(() {
      _speaking = true;
      _startWatchdog?.cancel();
    });
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler(_onError);
  }

  final FlutterTts _tts;

  /// Browsers load their voices a moment after the page, and Android's engine
  /// starts in the background, so an empty voice list isn't final. The first
  /// check waits up to [firstWait]; later checks (from speak) up to [retryWait].
  final Duration firstWait;
  final Duration retryWait;
  final Duration pollInterval;

  /// If speech hasn't started (or failed) this long after speak(), tell the
  /// learner rather than leave them waiting in silence.
  final Duration startTimeout;

  final _problems = StreamController<String>.broadcast();
  VoiceQuality _quality = VoiceQuality.unavailable;
  VoiceInfo? _voice;
  Future<void>? _loading;
  bool _checkedOnce = false;
  bool _speaking = false;
  Timer? _startWatchdog;
  int _request = 0;

  @override
  VoiceQuality get quality => _quality;

  @override
  VoiceInfo? get voice => _voice;

  @override
  Stream<String> get problems => _problems.stream;

  @override
  Future<void> init() {
    if (_quality != VoiceQuality.unavailable) return Future.value();
    return _loading ??= _loadVoice().whenComplete(() => _loading = null);
  }

  Future<void> _loadVoice() async {
    final wait = _checkedOnce ? retryWait : firstWait;
    _checkedOnce = true;
    try {
      final stopwatch = Stopwatch()..start();
      var voices = await _voices();
      while (voices.isEmpty && stopwatch.elapsed < wait) {
        await Future<void>.delayed(pollInterval);
        voices = await _voices();
      }
      if (voices.isEmpty) return; // still unavailable; speak() will check again

      final choice = chooseVoice(voices);
      if (choice != null) {
        await _tts.setVoice({'name': choice.voice['name']!, 'locale': choice.voice['locale']!});
        _quality = choice.quality;
        _voice = VoiceInfo(
            name: choice.voice['name']!,
            locale: choice.voice['locale'],
            quality: choice.quality,
            voiceCount: voices.length);
      } else {
        _quality = VoiceQuality.foreignAccent;
        _voice = VoiceInfo(
            name: await _defaultVoiceName(),
            locale: null,
            quality: VoiceQuality.foreignAccent,
            voiceCount: voices.length);
      }
    } catch (e) {
      debugPrint('Text to speech setup failed: $e');
    }
  }

  Future<List<Map<String, String>>> _voices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return [
      for (final v in raw.whereType<Map>())
        {for (final e in v.entries) '${e.key}': '${e.value}'}
    ].where((v) => (v['name'] ?? '').isNotEmpty && (v['locale'] ?? '').isNotEmpty).toList();
  }

  Future<String> _defaultVoiceName() async {
    if (kIsWeb) return 'Browser default voice';
    try {
      final v = await _tts.getDefaultVoice; // Android only
      if (v is Map && v['name'] != null) return '${v['name']} (device default)';
    } catch (_) {}
    return 'Device default voice';
  }

  @override
  Future<void> speak(String text, {bool slow = false}) async {
    if (text.trim().isEmpty) return;
    // Each speak() or stop() supersedes any speak() still waiting (for voices to
    // load, or for a cancel to finish), so only the latest request is heard.
    final request = ++_request;
    bool superseded() => request != _request;

    await init();
    if (superseded()) return;
    if (_quality == VoiceQuality.unavailable) {
      _problems.add(voiceQualityNote(VoiceQuality.unavailable));
      return;
    }
    try {
      await _stopSpeech();
      // Android and iOS treat 0.5 as normal speed; browsers use 1.0.
      await _tts.setSpeechRate(kIsWeb ? (slow ? 0.8 : 0.95) : (slow ? 0.38 : 0.47));
      if (superseded()) return;
      // Started before speak() because the start event can arrive before it returns.
      // Cancelled when speech starts, fails (reported by _onError) or is stopped.
      _startWatchdog?.cancel();
      _startWatchdog = Timer(startTimeout, () {
        _problems.add('Read aloud didn’t start. Tap “Hear again”, or use “Test voice” in the menu to check this device.');
      });
      await _tts.speak(text);
    } catch (e) {
      _startWatchdog?.cancel();
      _problems.add('Read aloud couldn’t play. Try “Hear again”.');
      debugPrint('Text to speech failed: $e');
    }
  }

  @override
  Future<void> stop() {
    _request++;
    return _stopSpeech();
  }

  Future<void> _stopSpeech() async {
    _startWatchdog?.cancel();
    final wasSpeaking = _speaking;
    await _tts.stop();
    if (!wasSpeaking) return;
    // A browser reports the cancel a moment later, and until then flutter_tts
    // ignores new speech. Wait for it so "Hear again" during speech isn't dropped.
    for (var i = 0; i < 25 && _speaking; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _speaking = false;
  }

  void _onError(dynamic message) {
    _speaking = false;
    _startWatchdog?.cancel();
    final code = '$message';
    // Our own stop() interrupts speech; that's not a problem to report.
    if (code == 'interrupted' || code == 'canceled') return;
    _problems.add(code == 'not-allowed'
        ? 'The browser blocked read aloud until you tap the page. Tap “Hear again” to play it.'
        : 'Read aloud couldn’t play ($code). Try “Hear again”.');
  }
}

String voiceQualityNote(VoiceQuality q) => switch (q) {
      VoiceQuality.kinyarwanda => 'Read aloud uses a Kinyarwanda voice.',
      VoiceQuality.swahiliApprox =>
        'No Kinyarwanda voice on this device, so a Swahili voice reads aloud. Treat its pronunciation as a rough guide.',
      VoiceQuality.foreignAccent =>
        'No Kinyarwanda or Swahili voice on this device, so read aloud will sound strongly accented.',
      VoiceQuality.unavailable => 'Read aloud isn’t available on this device.',
    };
