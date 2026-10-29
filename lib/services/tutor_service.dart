import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/chat.dart';
import '../models/scenario.dart';

class TutorException implements Exception {
  TutorException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to YOUR backend, never to the Claude API directly,
/// so the API key never ships inside the app.
class TutorService {
  TutorService({required this.baseUrl, this.appToken = '', http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String appToken;
  final http.Client _client;

  Future<TutorReply> nextTurn({
    required Level level,
    required String scenarioId,
    required List<ChatMessage> history,
  }) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$baseUrl/chat'),
            headers: {
              'content-type': 'application/json',
              if (appToken.isNotEmpty) 'x-app-token': appToken,
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
    } on SocketException {
      throw TutorException(
          'Can’t reach the tutor server. Check your internet connection and that the server is running.');
    } on http.ClientException {
      throw TutorException('Can’t reach the tutor server. Check the server address.');
    }

    if (res.statusCode != 200) {
      final code = _errorCode(res);
      throw TutorException(switch (code) {
        'rate_limited' => 'Too many messages at once. Wait a moment and try again.',
        'unauthorized' => 'The app token doesn’t match the server. Check APP_TOKEN.',
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
