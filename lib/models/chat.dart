enum Speaker { tutor, learner }

class Suggestion {
  const Suggestion({required this.rw, required this.en});
  final String rw;
  final String en;

  factory Suggestion.fromJson(Map<String, dynamic> j) =>
      Suggestion(rw: '${j['rw'] ?? ''}', en: '${j['en'] ?? ''}');
}

class TutorFeedback {
  const TutorFeedback({required this.message, required this.corrected, required this.wasCorrect});
  final String message;
  final String corrected;
  final bool wasCorrect;

  bool get hasCorrection => corrected.trim().isNotEmpty;
}

/// What the backend returns for one tutor turn.
class TutorReply {
  const TutorReply({
    required this.replyRw,
    required this.replyEn,
    required this.feedback,
    required this.suggestions,
  });

  final String replyRw;
  final String replyEn;
  final TutorFeedback? feedback;
  final List<Suggestion> suggestions;

  factory TutorReply.fromJson(Map<String, dynamic> j) {
    final fb = '${j['feedback'] ?? ''}'.trim();
    final rawSugs = j['suggestions'];
    return TutorReply(
      replyRw: '${j['reply_rw'] ?? ''}',
      replyEn: '${j['reply_en'] ?? ''}',
      feedback: fb.isEmpty
          ? null
          : TutorFeedback(
              message: fb,
              corrected: '${j['corrected'] ?? ''}',
              wasCorrect: j['was_correct'] == true,
            ),
      suggestions: rawSugs is List
          ? rawSugs
              .whereType<Map>()
              .map((m) => Suggestion.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }
}

/// One line in the conversation.
class ChatMessage {
  ChatMessage.tutor(this.text, {this.translation, this.suggestions = const []})
      : speaker = Speaker.tutor;

  ChatMessage.learner(this.text)
      : speaker = Speaker.learner,
        translation = null,
        suggestions = const [];

  final Speaker speaker;
  final String text;
  final String? translation;
  final List<Suggestion> suggestions;

  /// Set on a learner message once the tutor has checked it.
  TutorFeedback? feedback;

  Map<String, String> toHistoryJson() =>
      {'role': speaker == Speaker.tutor ? 'tutor' : 'learner', 'text': text};
}
