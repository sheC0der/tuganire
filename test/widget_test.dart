import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tuganire/main.dart';
import 'package:tuganire/models/scenario.dart';

void main() {
  testWidgets('Setup screen shows levels and situations', (tester) async {
    await tester.pumpWidget(const TuganireApp());

    expect(find.text('Tuganire'), findsOneWidget);
    for (final l in Level.values) {
      expect(find.widgetWithText(ChoiceChip, l.label), findsOneWidget);
    }
    // The first situations are on screen; the list scrolls for the rest.
    expect(find.text(scenarios.first.rw), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Start conversation'), 200);
    expect(find.text('Start conversation'), findsOneWidget);
  });

  testWidgets('Selecting a level and a situation updates the choice', (tester) async {
    await tester.pumpWidget(const TuganireApp());

    ChoiceChip chip(Level l) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, l.label));

    expect(chip(Level.beginner).selected, isTrue);
    expect(find.text(Level.beginner.hint), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, Level.advanced.label));
    await tester.pump();

    expect(chip(Level.beginner).selected, isFalse);
    expect(chip(Level.advanced).selected, isTrue);
    expect(find.text(Level.advanced.hint), findsOneWidget);

    ListTile tile(Scenario s) => tester.widget<ListTile>(find.widgetWithText(ListTile, s.rw));
    final second = scenarios[1];

    expect(tile(scenarios.first).selected, isTrue);
    await tester.tap(find.text(second.rw));
    await tester.pump();

    expect(tile(scenarios.first).selected, isFalse);
    expect(tile(second).selected, isTrue);
  });
}
