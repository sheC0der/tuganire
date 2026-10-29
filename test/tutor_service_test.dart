import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tuganire/config.dart';
import 'package:tuganire/models/chat.dart';
import 'package:tuganire/models/scenario.dart';
import 'package:tuganire/services/auth_service.dart';
import 'package:tuganire/services/tutor_service.dart';

const _reply = {'reply_rw': 'Muraho', 'reply_en': 'Hello', 'suggestions': []};

void main() {
  late int unauthorizedCalls;
  setUp(() => unauthorizedCalls = 0);

  TutorService service(MockClientHandler handler,
          {String baseUrl = 'https://tutor.example', Future<String?> Function()? token}) =>
      TutorService(
        baseUrl: baseUrl,
        accessToken: token ?? () async => 'token-123',
        onUnauthorized: () async => unauthorizedCalls++,
        client: MockClient(handler),
      );

  Future<TutorReply> turn(TutorService s) =>
      s.nextTurn(level: Level.beginner, scenarioId: 'greet', history: [ChatMessage.learner('Muraho')]);

  test('posts to /api/chat with the bearer token', () async {
    late http.Request sent;
    final reply = await turn(service((req) async {
      sent = req;
      return http.Response(jsonEncode(_reply), 200);
    }));

    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://tutor.example/api/chat');
    expect(sent.headers['authorization'], 'Bearer token-123');
    expect(jsonDecode(sent.body), {
      'level': 'beginner',
      'scenarioId': 'greet',
      'history': [
        {'role': 'learner', 'text': 'Muraho'}
      ],
    });
    expect(reply.replyRw, 'Muraho');
  });

  test('a 401 signs the user out', () async {
    final s = service((_) async => http.Response('{"error":"unauthorized"}', 401));
    await expectLater(turn(s), throwsA(isA<TutorException>()));
    expect(unauthorizedCalls, 1);
  });

  test('no session signs out without calling the server', () async {
    var called = false;
    final s = service((_) async {
      called = true;
      return http.Response('{}', 200);
    }, token: () async => null);
    await expectLater(turn(s), throwsA(isA<TutorException>()));
    expect(called, isFalse);
    expect(unauthorizedCalls, 1);
  });

  test('a 403 explains the account is not allowed, without signing out', () async {
    final s = service((_) async => http.Response('{"error":"forbidden"}', 403));
    await expectLater(
        turn(s), throwsA(isA<TutorException>().having((e) => e.message, 'message', contains('isn’t allowed'))));
    expect(unauthorizedCalls, 0);
  });

  test('sign-in server outage is reported, not treated as signed out', () async {
    final s = service((_) async => http.Response('{}', 200),
        token: () async => throw AuthFailure('Can’t reach the sign-in server.'));
    await expectLater(turn(s), throwsA(isA<TutorException>()));
    expect(unauthorizedCalls, 0);
  });

  test('the Railway placeholder URL gives a clear error', () async {
    final s = service((_) async => http.Response('{}', 200), baseUrl: AppConfig.railwayUrlPlaceholder);
    await expectLater(
        turn(s), throwsA(isA<TutorException>().having((e) => e.message, 'message', contains('BACKEND_URL'))));
  });
}
