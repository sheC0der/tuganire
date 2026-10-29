import 'package:flutter/material.dart';

import '../models/chat.dart';

class TutorBubble extends StatelessWidget {
  const TutorBubble({
    super.key,
    required this.message,
    required this.showTranslation,
    required this.showSuggestions,
    required this.onSpeak,
    required this.onPickSuggestion,
  });

  final ChatMessage message;
  final bool showTranslation;
  final bool showSuggestions;
  final void Function(String text) onSpeak;
  final void Function(String text) onPickSuggestion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(message.text, style: tt.titleMedium),
                  ),
                  if (message.translation != null)
                    _Translation(text: message.translation!, initiallyShown: showTranslation),
                  TextButton.icon(
                    onPressed: () => onSpeak(message.text),
                    icon: const Icon(Icons.volume_up_outlined, size: 18),
                    label: const Text('Hear again'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            if (showSuggestions && message.suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Not sure what to say? Tap one to use it:',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              for (final s in message.suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    onPressed: () => onPickSuggestion(s.rw),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.rw, style: tt.bodyMedium?.copyWith(color: cs.onSurface)),
                        if (s.en.isNotEmpty)
                          Text(s.en, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Translation line. When translations are off, shows a "Show meaning" button instead.
class _Translation extends StatefulWidget {
  const _Translation({required this.text, required this.initiallyShown});
  final String text;
  final bool initiallyShown;

  @override
  State<_Translation> createState() => _TranslationState();
}

class _TranslationState extends State<_Translation> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.initiallyShown || _revealed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, right: 6),
        child: Text(widget.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      );
    }
    return TextButton(
      onPressed: () => setState(() => _revealed = true),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        visualDensity: VisualDensity.compact,
      ),
      child: const Text('Show meaning'),
    );
  }
}

class LearnerBubble extends StatelessWidget {
  const LearnerBubble({super.key, required this.message, required this.onSpeak});

  final ChatMessage message;
  final void Function(String text) onSpeak;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fb = message.feedback;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(message.text,
                  style: tt.titleMedium?.copyWith(color: cs.onSecondaryContainer)),
            ),
            if (fb != null) ...[
              const SizedBox(height: 8),
              _FeedbackCard(feedback: fb, onSpeak: onSpeak),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback, required this.onSpeak});
  final TutorFeedback feedback;
  final void Function(String text) onSpeak;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final good = feedback.wasCorrect && !feedback.hasCorrection;
    final bg = good ? cs.tertiaryContainer : cs.primaryContainer;
    final fg = good ? cs.onTertiaryContainer : cs.onPrimaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(good ? 'Well done' : 'Correction',
              style: tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(feedback.message, style: tt.bodyMedium?.copyWith(color: fg)),
          if (feedback.hasCorrection) ...[
            const SizedBox(height: 6),
            Text(feedback.corrected,
                style: tt.bodyLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
            TextButton.icon(
              onPressed: () => onSpeak(feedback.corrected),
              icon: Icon(Icons.volume_up_outlined, size: 18, color: fg),
              label: Text('Hear it', style: TextStyle(color: fg)),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ] else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}
