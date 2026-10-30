import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tuganire/services/remote_voice_service.dart';
import 'package:tuganire/services/voice_service.dart';

class _FakeOutput implements AudioOutput {
  final played = <(String, double)>[];
  int stops = 0;
  Object? playError;

  @override
  Future<void> play(Uint8List wav, {double rate = 1.0}) async {
    if (playError != null) throw playError!;
    played.add((utf8.decode(wav), rate));
  }

  @override
  Future<void> stop() async => stops++;
}

class _FakeDeviceVoice implements VoiceService {
  final spoken = <(String, bool)>[];
  final _problems = StreamController<String>.broadcast();

  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text, {bool slow = false}) async => spoken.add((text, slow));
  @override
  Future<void> stop() async {}
  @override
  VoiceQuality get quality => VoiceQuality.swahiliApprox;
  @override
  VoiceInfo? get voice =>
      const VoiceInfo(name: 'Swahili', locale: 'sw-KE', quality: VoiceQuality.swahiliApprox, voiceCount: 3);
  @override
  Stream<String> get problems => _problems.stream;
  @override
  ValueListenable<String?> get preparing => ValueNotifier(null);
}

void main() {
  late _FakeOutput output;
  late _FakeDeviceVoice device;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) server;
  late int signOuts;
  late List<String> problems;

  /// The server answers each text with audio bytes that spell it, so tests can see what played.
  Future<http.Response> audio(http.Request req) async => http.Response.bytes(
      utf8.encode('wav:${jsonDecode(req.body)['text']}'), 200,
      headers: {'content-type': 'audio/wav', 'x-tts-model': 'facebook/mms-tts-kin'});

  RemoteVoiceService service({Duration retryAfter = const Duration(minutes: 1)}) {
    final voice = RemoteVoiceService(
      baseUrl: 'https://tutor.example',
      accessToken: () async => 'token',
      onUnauthorized: () async => signOuts++,
      fallback: device,
      output: output,
      client: MockClient((req) {
        requests.add(req);
        return server(req);
      }),
      timeout: const Duration(milliseconds: 100),
      retryAfter: retryAfter,
    );
    voice.problems.listen(problems.add);
    return voice;
  }

  setUp(() {
    output = _FakeOutput();
    device = _FakeDeviceVoice();
    requests = [];
    server = audio;
    signOuts = 0;
    problems = [];
  });

  test('plays the server’s Kinyarwanda audio, slower for beginners', () async {
    final voice = service();
    await voice.speak('Muraho', slow: true);

    expect(requests.single.url.toString(), 'https://tutor.example/api/tts');
    expect(requests.single.headers['authorization'], 'Bearer token');
    expect(jsonDecode(requests.single.body), {'text': 'Muraho'});
    expect(output.played, [('wav:Muraho', 0.8)]);
    expect(device.spoken, isEmpty);
    expect(voice.quality, VoiceQuality.kinyarwanda);
    expect(voice.voice!.name, contains('facebook/mms-tts-kin'));
    expect(problems, isEmpty);
  });

  test('"Hear again" replays from memory without asking the server', () async {
    final voice = service();
    await voice.speak('Muraho');
    await voice.speak('Muraho');

    expect(requests, hasLength(1));
    expect(output.played, [('wav:Muraho', 1.0), ('wav:Muraho', 1.0)]);
  });

  test('shows the text as preparing while its audio is generated', () async {
    final reply = Completer<http.Response>();
    server = (_) => reply.future;
    final voice = service();

    final speaking = voice.speak('Muraho');
    await Future<void>.delayed(Duration.zero);
    expect(voice.preparing.value, 'Muraho');

    reply.complete(http.Response.bytes(utf8.encode('wav'), 200));
    await speaking;
    expect(voice.preparing.value, isNull);
  });

  test('when the TTS service fails, the device voice reads aloud with one short notice', () async {
    server = (_) async => http.Response('{"error":"tts_not_configured"}', 503);
    final voice = service();

    await voice.speak('Muraho', slow: true);
    await voice.speak('Amakuru?');
    await Future<void>.delayed(Duration.zero);

    expect(device.spoken, [('Muraho', true), ('Amakuru?', false)]);
    expect(output.played, isEmpty);
    expect(problems, [contains('device’s voice')], reason: 'one notice, not one per message');
    expect(requests, hasLength(1), reason: 'skips the server for a while after it fails');
    expect(voice.quality, VoiceQuality.swahiliApprox);
    expect(voice.voice!.name, 'Swahili');
  });

  test('a slow server times out and falls back', () async {
    server = (_) => Completer<http.Response>().future; // never answers
    final voice = service();

    await voice.speak('Muraho');

    expect(device.spoken, [('Muraho', false)]);
    expect(voice.preparing.value, isNull);
  });

  test('tries the server again once it recovers, and tells the learner again after a new outage', () async {
    server = (_) async => http.Response('', 502);
    final voice = service(retryAfter: Duration.zero);

    await voice.speak('one');
    server = audio;
    await voice.speak('two');
    server = (_) async => http.Response('', 502);
    await voice.speak('three');
    await Future<void>.delayed(Duration.zero);

    expect(device.spoken.map((s) => s.$1), ['one', 'three']);
    expect(output.played.map((p) => p.$1), ['wav:two']);
    expect(problems, hasLength(2));
    expect(voice.quality, VoiceQuality.swahiliApprox);
  });

  test('only the latest request plays when a new one arrives while audio loads', () async {
    final first = Completer<http.Response>();
    server = (req) => jsonDecode(req.body)['text'] == 'first' ? first.future : audio(req);
    final voice = service();

    final pending = voice.speak('first');
    await Future<void>.delayed(Duration.zero);
    await voice.speak('second');
    first.complete(http.Response.bytes(utf8.encode('wav:first'), 200));
    await pending;

    expect(output.played.map((p) => p.$1), ['wav:second']);
    expect(device.spoken, isEmpty);
  });

  test('stop() cancels audio that is still loading', () async {
    final reply = Completer<http.Response>();
    server = (_) => reply.future;
    final voice = service();

    final pending = voice.speak('Muraho');
    await Future<void>.delayed(Duration.zero);
    await voice.stop();
    expect(voice.preparing.value, isNull);
    reply.complete(http.Response.bytes(utf8.encode('wav'), 200));
    await pending;

    expect(output.played, isEmpty);
  });

  test('a rejected token signs the learner out', () async {
    server = (_) async => http.Response('{"error":"unauthorized"}', 401);
    final voice = service();

    await voice.speak('Muraho');

    expect(signOuts, 1);
    expect(output.played, isEmpty);
    expect(device.spoken, isEmpty);
  });

  test('a blocked or failed playback is reported, not silent', () async {
    output.playError = Exception('NotAllowedError: play() failed because the user didn’t interact');
    final voice = service();

    await voice.speak('Muraho');
    await Future<void>.delayed(Duration.zero);

    expect(problems, [contains('blocked')]);
  });
}
