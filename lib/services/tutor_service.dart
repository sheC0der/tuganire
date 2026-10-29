import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/chat.dart';
import '../models/scenario.dart';
import 'auth_service.dart';

class TutorException implements Exception {
  TutorException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to YOUR backend, never to the Claude API directly,
/// so the API key never ships inside the app.
class TutorService {
  TutorService({
    required this.baseUrl,
    required this.accessToken,
    required this.onUnauthorized,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;

  /// The signed-in user's token, sent as `Authorization: Bearer <token>`.
  final Future<String?> Function() accessToken;

  /// Called when the backend rejects the token; signs the user out.
  final Future<void> Function() onUnauthorized;

  final http.Client _client;

  static const _sessionEnded = 'Your session has ended. Please sign in again.';

  Future<TutorReply> nextTurn({
    required Level level,
    required String scenarioId,
    required List<ChatMessage> history,
  }) async {
    if (baseUrl == AppConfig.railwayUrlPlaceholder) {
      throw TutorException(
          'The server address isn’t set. Build the app with --dart-define=BACKEND_URL=<your Railway URL>.');
    }

    final String? token;
    try {
      token = await accessToken();
    } on AuthFailure catch (e) {
      throw TutorException(e.message);
    }
    if (token == null) {
      await onUnauthorized();
      throw TutorException(_sessionEnded);
    }

    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'level': level.name,
              'scenarioId': scenarioId,
              'history': history.map((m) => m.toHistoryJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw TutorException('The tutor took too long to answer. Try again.');
    } on http.ClientException {
      // http wraps network failures (no connection, server down, bad address) in ClientException.
      throw TutorException(
          'Can’t reach the tutor server. Check your internet connection and the server address.');
    }

    if (res.statusCode == 401) {
      await onUnauthorized();
      throw TutorException(_sessionEnded);
    }
    if (res.statusCode != 200) {
      final code = _errorCode(res);
      throw TutorException(switch (code) {
        'forbidden' => 'This account isn’t allowed to use Tuganire. Ask the owner to add your email.',
        'auth_unavailable' => 'Couldn’t check your sign-in just now. Try again in a moment.',
        'rate_limited' => 'Too many messages at once. Wait a moment and try again.',
        'bad_reply' => 'The tutor’s answer came back garbled. Try again.',
        _ => 'The tutor couldn’t reply (error ${res.statusCode}). Try again.',
      });
    }

    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final reply = TutorReply.fromJson(json);
    if (reply.replyRw.trim().isEmpty) {
      throw TutorException('The tutor sent an empty reply. Try again.');
    }
    return reply;
  }

  String? _errorCode(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map)['error'] as String?;
    } catch (_) {
      return null;
    }
  }
}
