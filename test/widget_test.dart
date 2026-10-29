import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tuganire/main.dart';
import 'package:tuganire/models/scenario.dart';
import 'package:tuganire/screens/setup_screen.dart';
import 'package:tuganire/screens/sign_in_screen.dart';

import 'fake_auth_service.dart';

void main() {
  group('Setup screen', () {
    testWidgets('shows levels and situations', (tester) async {
      await tester.pumpWidget(TuganireApp(auth: FakeAuthService(signedIn: true)));

      expect(find.text('Tuganire'), findsOneWidget);
      for (final l in Level.values) {
        expect(find.widgetWithText(ChoiceChip, l.label), findsOneWidget);
      }
      // The first situations are on screen; the list scrolls for the rest.
      expect(find.text(scenarios.first.rw), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Start conversation'), 200);
      expect(find.text('Start conversation'), findsOneWidget);
    });

    testWidgets('selecting a level and a situation updates the choice', (tester) async {
      await tester.pumpWidget(TuganireApp(auth: FakeAuthService(signedIn: true)));

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
  });

  group('Sign-in', () {
    testWidgets('signed-out users see sign-in with no sign-up option', (tester) async {
      await tester.pumpWidget(TuganireApp(auth: FakeAuthService()));

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
      expect(find.textContaining(RegExp('sign up|create account|register', caseSensitive: false)), findsNothing);
    });

    testWidgets('wrong password shows an error and stays on sign-in', (tester) async {
      await tester.pumpWidget(TuganireApp(auth: FakeAuthService()));

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'learner@example.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'nope');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('empty fields are caught before calling the server', (tester) async {
      await tester.pumpWidget(TuganireApp(auth: FakeAuthService()));

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.text('Enter your email and password.'), findsOneWidget);
    });

    testWidgets('signing in opens the setup screen, signing out returns', (tester) async {
      final auth = FakeAuthService();
      await tester.pumpWidget(TuganireApp(auth: auth));

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'learner@example.com');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(SetupScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(auth.signOutCalls, 1);
    });

    testWidgets('signing out from a pushed screen closes it and shows sign-in', (tester) async {
      final auth = FakeAuthService(signedIn: true);
      await tester.pumpWidget(TuganireApp(auth: auth));

      // Stands in for the chat screen, where a 401 from the backend signs the user out.
      Navigator.of(tester.element(find.byType(SetupScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('pushed screen'))));
      await tester.pumpAndSettle();
      expect(find.text('pushed screen'), findsOneWidget);

      await auth.signOut();
      await tester.pumpAndSettle();

      expect(find.text('pushed screen'), findsNothing);
      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });
}
