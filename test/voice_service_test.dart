import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:tuganire/services/voice_service.dart';

/// Stands in for the platform side of flutter_tts (the browser or Android engine).
class _FakeEngine {
  _FakeEngine(this.tts);
  final FlutterTts tts;

  /// Voices returned by getVoices, one list per call; the last one repeats.
  List<List<Map<String, String>>> voiceLists = [[]];
  final calls = <MethodCall>[];

  /// speak/stop calls and the cancel event, in the order they happened.
  final events = <String>[];

  /// Whether an utterance is playing, like the browser's speechSynthesis.
  bool playing = false;

  /// Set to false to simulate speech that never starts (a stuck browser queue).
  bool startsSpeaking = true;

  int _getVoicesCalls = 0;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'getVoices':
        final i = _getVoicesCalls++;
        return voiceLists[i < voiceLists.length ? i : voiceLists.length - 1];
      case 'speak':
        events.add('speak');
        if (startsSpeaking) {
          playing = true;
          await _fromPlatform('speak.onStart');
        }
      case 'stop':
        if (playing) {
          events.add('stop');
          playing = false;
          // Browsers report the cancel after stop() returns.
          Future<void>.delayed(const Duration(milliseconds: 60), () {
            events.add('interrupted');
            return _fromPlatform('speak.onError', 'interrupted');
          });
        }
    }
    return 1;
  }

  Future<void> _fromPlatform(String method, [Object? args]) =>
      tts.platformCallHandler(MethodCall(method, args));

  List<String> get methods => calls.map((c) => c.method).toList();
  Object? lastArgs(String method) => calls.lastWhere((c) => c.method == method).arguments;
}

const _channel = MethodChannel('flutter_tts');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterTts tts;
  late _FakeEngine engine;

  setUp(() {
    tts = FlutterTts();
    engine = _FakeEngine(tts);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, engine.handle);
  });
  tearDown(() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

  DeviceVoiceService service() => DeviceVoiceService(
        tts: tts,
        firstWait: const Duration(milliseconds: 500),
        retryWait: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 20),
        startTimeout: const Duration(milliseconds: 150),
      );

  group('chooseVoice', () {
    test('prefers Kinyarwanda, then Swahili, matching on language', () {
      final en = {'name': 'David', 'locale': 'en-US'};
      final sw = {'name': 'Swahili Kenya', 'locale': 'sw-KE'};
      final rw = {'name': 'Kinyarwanda', 'locale': 'rw_RW'};

      expect(chooseVoice([en, sw, rw])!.voice, rw);
      expect(chooseVoice([en, sw, rw])!.quality, VoiceQuality.kinyarwanda);
      expect(chooseVoice([en, sw])!.voice, sw);
      expect(chooseVoice([en, sw])!.quality, VoiceQuality.swahiliApprox);
      expect(chooseVoice([en]), isNull, reason: 'null means use the default voice');
    });

    test('prefers Edge’s natural Swahili voices', () {
      final plain = {'name': 'Microsoft Swahili Desktop', 'locale': 'sw-KE'};
      final natural = {'name': 'Microsoft Rafiki Online (Natural) - Swahili (Kenya)', 'locale': 'sw-KE'};
      expect(chooseVoice([plain, natural])!.voice, natural);
    });

    test('does not match languages that merely start with the same letters', () {
      expect(chooseVoice([{'name': 'x', 'locale': 'rwk-TZ'}, {'name': 'y', 'locale': 'swc-CD'}]), isNull);
    });

    test('skips Android voices that are not installed', () {
      final missing = {'name': 'sw-ke-x-network', 'locale': 'sw-KE', 'features': 'notInstalled\tnetworkTts'};
      final installed = {'name': 'sw-ke-x-local', 'locale': 'sw-KE', 'features': 'embeddedTts'};
      expect(chooseVoice([missing, installed])!.voice, installed);
      expect(chooseVoice([missing]), isNull);
    });
  });

  test('waits for voices that load after startup, then picks Swahili', () async {
    engine.voiceLists = [
      [],
      [],
      [
        {'name': 'David', 'locale': 'en-US'},
        {'name': 'Rafiki (Natural)', 'locale': 'sw-KE'},
      ],
    ];
    final voice = service();
    await voice.init();

    expect(voice.quality, VoiceQuality.swahiliApprox);
    expect(voice.voice!.name, 'Rafiki (Natural)');
    expect(voice.voice!.locale, 'sw-KE');
    expect(voice.voice!.voiceCount, 2);
    expect(engine.lastArgs('setVoice'), {'name': 'Rafiki (Natural)', 'locale': 'sw-KE'});
  });

  test('uses the default voice when there is no Kinyarwanda or Swahili voice', () async {
    engine.voiceLists = [
      [
        {'name': 'David', 'locale': 'en-US'}
      ]
    ];
    final voice = service();
    await voice.speak('Muraho');

    expect(voice.quality, VoiceQuality.foreignAccent);
    expect(engine.methods, isNot(contains('setVoice')));
    expect(engine.lastArgs('speak'), 'Muraho');
  });

  test('an empty list is not final: speak() checks again and then plays', () async {
    final voice = service();
    await voice.init();
    expect(voice.quality, VoiceQuality.unavailable);

    engine.voiceLists = [
      [
        {'name': 'Swahili', 'locale': 'sw-TZ'}
      ]
    ];
    final problems = <String>[];
    voice.problems.listen(problems.add);
    await voice.speak('Muraho');

    expect(voice.quality, VoiceQuality.swahiliApprox);
    expect(engine.lastArgs('speak'), 'Muraho');
    expect(problems, isEmpty);
  });

  test('when no voice can be used, speak() reports it instead of staying silent', () async {
    final voice = service();
    final problems = <String>[];
    voice.problems.listen(problems.add);

    await voice.speak('Muraho');
    await Future<void>.delayed(Duration.zero);

    expect(engine.methods, isNot(contains('speak')));
    expect(problems, [voiceQualityNote(VoiceQuality.unavailable)]);
  });

  test('a blocked or failed utterance is reported; our own stop() is not', () async {
    engine.voiceLists = [
      [
        {'name': 'Swahili', 'locale': 'sw-KE'}
      ]
    ];
    final voice = service();
    final problems = <String>[];
    voice.problems.listen(problems.add);
    await voice.init();

    await tts.platformCallHandler(const MethodCall('speak.onError', 'interrupted'));
    await tts.platformCallHandler(const MethodCall('speak.onError', 'not-allowed'));
    await tts.platformCallHandler(const MethodCall('speak.onError', 'synthesis-failed'));
    await Future<void>.delayed(Duration.zero);

    expect(problems, hasLength(2));
    expect(problems[0], contains('blocked'));
    expect(problems[1], contains('synthesis-failed'));
  });

  test('"Hear again" during speech waits for the browser to finish cancelling', () async {
    engine.voiceLists = [
      [
        {'name': 'Swahili', 'locale': 'sw-KE'}
      ]
    ];
    final voice = service();
    await voice.speak('Mwaramutse');
    expect(engine.playing, isTrue);

    await voice.speak('Mwaramutse');

    // flutter_tts on web drops speech that arrives before the cancel event,
    // so the second speak must come after it.
    expect(engine.events, ['speak', 'stop', 'interrupted', 'speak']);
  });

  test('speech that never starts is reported, not left silent', () async {
    engine.voiceLists = [
      [
        {'name': 'Swahili', 'locale': 'sw-KE'}
      ]
    ];
    engine.startsSpeaking = false;
    final voice = service();
    final problems = <String>[];
    voice.problems.listen(problems.add);

    await voice.speak('Muraho');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(problems, [contains('didn’t start')]);
  });

  test('a short phrase that starts and finishes quickly raises no alarm', () async {
    engine.voiceLists = [
      [
        {'name': 'Swahili', 'locale': 'sw-KE'}
      ]
    ];
    final voice = service();
    final problems = <String>[];
    voice.problems.listen(problems.add);

    await voice.speak('Yego');
    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(problems, isEmpty);
  });

  test('requests made while voices load: only the latest is spoken', () async {
    engine.voiceLists = [
      [],
      [],
      [
        {'name': 'Swahili', 'locale': 'sw-KE'}
      ],
    ];
    final voice = service();
    final problems = <String>[];
    voice.problems.listen(problems.add);

    // The first reply and a "Hear again" tap both arrive before voices load.
    await Future.wait([voice.speak('first reply'), voice.speak('hear again')]);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(engine.calls.where((c) => c.method == 'speak').map((c) => c.arguments), ['hear again']);
    expect(problems, isEmpty, reason: 'no orphaned "didn’t start" alarm');
  });

  test('stop() cancels a speak() that is still waiting for voices', () async {
    engine.voiceLists = [
      [],
      [],
      [
        {'name': 'Swahili', 'locale': 'sw-KE'}
      ],
    ];
    final voice = service();
    final pending = voice.speak('Muraho');
    await voice.stop(); // e.g. the learner turned read aloud off or sent a message
    await pending;

    expect(engine.methods, isNot(contains('speak')));
  });
}
