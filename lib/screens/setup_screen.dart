import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/conversation_controller.dart';
import '../models/scenario.dart';
import '../services/auth_service.dart';
import '../services/tutor_service.dart';
import '../services/voice_service.dart';
import 'chat_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  Level _level = Level.beginner;
  Scenario _scenario = scenarios.first;

  void _start() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (ctx) => ConversationController(
          tutor: ctx.read<TutorService>(),
          voice: ctx.read<VoiceService>(),
          level: _level,
          scenario: _scenario,
        )..start(),
        child: const ChatScreen(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Tuganire', style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: () => context.read<AuthService>().signOut(),
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Let’s talk. Practise Kinyarwanda in real conversations with Mwarimu, your tutor.',
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 28),
            Text('Your level', style: tt.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in Level.values)
                  ChoiceChip(
                    label: Text(l.label),
                    tooltip: l.hint,
                    selected: _level == l,
                    onSelected: (_) => setState(() => _level = l),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_level.hint, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            Text('Situation', style: tt.titleMedium),
            const SizedBox(height: 8),
            for (final s in scenarios)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  selected: _scenario.id == s.id,
                  selectedTileColor: cs.primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _scenario.id == s.id ? cs.primary : cs.outlineVariant),
                  ),
                  title: Text(s.rw),
                  subtitle: Text(s.en),
                  trailing: _scenario.id == s.id ? const Icon(Icons.check) : null,
                  onTap: () => setState(() => _scenario = s),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Start conversation'),
            ),
          ],
        ),
      ),
    );
  }
}
