import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/conversation_controller.dart';
import '../models/chat.dart';
import '../services/speech_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  late final SpeechService _speech = context.read<SpeechService>();

  bool _speechReady = false;
  bool _micKinyarwanda = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final voice = context.read<VoiceService>();
    final ok = await _speech.init();
    await voice.init();
    if (!mounted) return;
    setState(() {
      _speechReady = ok;
      _micKinyarwanda = _speech.supportsKinyarwanda;
      final notes = <String>[];
      if (!ok) {
        notes.add('Speaking isn’t available on this phone, so type your answers.');
      } else if (!_speech.supportsKinyarwanda) {
        notes.add(_speech.canTryKinyarwanda
            ? 'The mic starts in English. Tap EN under it to try Kinyarwanda.'
            : 'This phone can’t recognise spoken Kinyarwanda, so the mic listens in English.');
      }
      if (voice.quality != VoiceQuality.kinyarwanda) notes.add(voiceQualityNote(voice.quality));
      _status = notes.isEmpty ? null : notes.join(' ');
    });
    _speech.lastError.addListener(_onSpeechError);
  }

  void _onSpeechError() {
    final e = _speech.lastError.value;
    if (e != null && mounted) setState(() => _status = e);
  }

  Future<void> _toggleMic() async {
    if (!_speechReady) {
      setState(() => _status = 'Speaking isn’t available on this phone. Type your answer instead.');
      return;
    }
    if (_speech.listening.value) {
      await _speech.stop();
      return;
    }
    await context.read<VoiceService>().stop();
    if (!mounted) return;
    setState(() => _status = 'Listening… speak now');
    await _speech.listen(
      kinyarwanda: _micKinyarwanda,
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() {
          _input.text = text;
          _input.selection = TextSelection.collapsed(offset: text.length);
          if (isFinal) _status = 'Check the text, then send.';
        });
      },
    );
  }

  /// Speaks a short phrase and shows which voice the device used, to check read aloud.
  Future<void> _testVoice() async {
    const phrase = 'Muraho! Amakuru yawe?';
    final voice = context.read<VoiceService>();
    await voice.speak(phrase);
    if (!mounted) return;
    final info = voice.voice;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test voice'),
        content: Text([
          'Said: “$phrase” (Hello! How are you?)',
          if (info == null)
            'No voice was found, so nothing could play.'
          else ...[
            'Voice: ${info.name}',
            'Language: ${info.locale ?? 'the device’s default'}',
            voiceQualityNote(info.quality),
            if (info.voiceCount != null) 'Voices on this device: ${info.voiceCount}',
          ],
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => voice.speak(phrase), child: const Text('Play again')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  void _send(ConversationController c) {
    final text = _input.text;
    if (text.trim().isEmpty || c.isThinking) return;
    if (_speech.listening.value) _speech.stop();
    _input.clear();
    setState(() => _status = null);
    c.send(text);
  }

  @override
  void dispose() {
    _speech.lastError.removeListener(_onSpeechError);
    _speech.stop();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConversationController>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (c.voiceProblem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final problem = c.takeVoiceProblem();
        if (problem != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
        }
      });
    }

    final lastTutorIndex = c.messages.lastIndexWhere((m) => m.speaker == Speaker.tutor);
    final items = <Widget>[
      for (var i = 0; i < c.messages.length; i++)
        c.messages[i].speaker == Speaker.tutor
            ? TutorBubble(
                key: ObjectKey(c.messages[i]),
                message: c.messages[i],
                showTranslation: c.showTranslations,
                showSuggestions: i == lastTutorIndex && !c.isThinking,
                preparingSpeech: c.preparingSpeech,
                onSpeak: c.speak,
                onPickSuggestion: (t) => setState(() {
                  _input.text = t;
                  _input.selection = TextSelection.collapsed(offset: t.length);
                }),
              )
            : LearnerBubble(
                key: ObjectKey(c.messages[i]),
                message: c.messages[i],
                preparingSpeech: c.preparingSpeech,
                onSpeak: c.speak,
              ),
      if (c.isThinking)
        Text('Mwarimu is thinking…',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
      if (c.error != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(child: Text(c.error!, style: TextStyle(color: cs.onErrorContainer))),
              TextButton(onPressed: c.retry, child: const Text('Try again')),
            ],
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.scenario.rw),
            Text('${c.scenario.en}, ${c.level.name}', style: tt.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: c.showTranslations ? 'Hide translations' : 'Show translations',
            onPressed: c.toggleTranslations,
            icon: Icon(c.showTranslations ? Icons.translate : Icons.translate_outlined),
            isSelected: c.showTranslations,
          ),
          IconButton(
            tooltip: c.readAloud ? 'Turn off read aloud' : 'Turn on read aloud',
            onPressed: c.toggleReadAloud,
            icon: Icon(c.readAloud ? Icons.volume_up : Icons.volume_off),
          ),
          PopupMenuButton<void>(
            tooltip: 'More',
            itemBuilder: (_) => [
              PopupMenuItem(onTap: _testVoice, child: const Text('Test voice')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: conversationMaxWidth),
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    reverse: true, // newest at the bottom, auto-scrolls as messages arrive
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (_, i) => items[items.length - 1 - i],
                    // Keeps each bubble's state (e.g. a revealed translation) with its message
                    // as new messages shift positions in the reversed list.
                    findItemIndexCallback: (key) {
                      final i = items.indexWhere((w) => w.key == key);
                      return i < 0 ? null : items.length - 1 - i;
                    },
                  ),
                ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Text(_status!, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                _Composer(
                  controller: _input,
                  speech: _speech,
                  speechReady: _speechReady,
                  micKinyarwanda: _micKinyarwanda,
                  canUseKinyarwanda: _speech.canTryKinyarwanda,
                  onToggleMicLanguage: () => setState(() => _micKinyarwanda = !_micKinyarwanda),
                  onMic: _toggleMic,
                  onSend: () => _send(c),
                  sending: c.isThinking,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.speech,
    required this.speechReady,
    required this.micKinyarwanda,
    required this.canUseKinyarwanda,
    required this.onToggleMicLanguage,
    required this.onMic,
    required this.onSend,
    required this.sending,
  });

  final TextEditingController controller;
  final SpeechService speech;
  final bool speechReady;
  final bool micKinyarwanda;
  final bool canUseKinyarwanda;
  final VoidCallback onToggleMicLanguage;
  final VoidCallback onMic;
  final VoidCallback onSend;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: speech.listening,
                builder: (_, listening, _) => IconButton.filledTonal(
                  tooltip: listening ? 'Stop listening' : 'Speak your answer',
                  onPressed: speechReady ? onMic : null,
                  isSelected: listening,
                  icon: Icon(listening ? Icons.stop : Icons.mic),
                ),
              ),
              // Which language the mic listens for. RW when the device supports it, and always on web.
              GestureDetector(
                onTap: canUseKinyarwanda ? onToggleMicLanguage : null,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(micKinyarwanda ? 'RW' : 'EN',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(hintText: 'Andika hano… (type here)'),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IconButton.filled(
              tooltip: 'Send',
              onPressed: sending ? null : onSend,
              icon: const Icon(Icons.send),
            ),
          ),
        ],
      ),
    );
  }
}
