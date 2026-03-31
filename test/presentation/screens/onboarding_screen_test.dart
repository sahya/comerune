import 'package:comerune/application/onboarding/onboarding_store.dart';
import 'package:comerune/presentation/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('showOnboardingDialog', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesOnboardingStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesOnboardingStore(prefs: prefs);
    });

    Future<void> showDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              // Show dialog after first frame.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showOnboardingDialog(
                  context: context,
                  onboardingStore: store,
                );
              });
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows welcome page on initial display', (
      WidgetTester tester,
    ) async {
      await showDialog(tester);

      expect(find.text('comerune へようこそ'), findsOneWidget);
      expect(find.text('つぎへ'), findsOneWidget);
    });

    testWidgets('navigates to next page on button tap', (
      WidgetTester tester,
    ) async {
      await showDialog(tester);

      await tester.tap(find.text('つぎへ'));
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムでコメントを表示'), findsOneWidget);
    });

    testWidgets('navigates forward by swiping', (WidgetTester tester) async {
      await showDialog(tester);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムでコメントを表示'), findsOneWidget);
    });

    testWidgets('shows start button on last page', (
      WidgetTester tester,
    ) async {
      await showDialog(tester);

      for (int i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
      }

      expect(find.text('準備完了！'), findsOneWidget);
      expect(find.text('はじめる'), findsOneWidget);
      expect(find.text('つぎへ'), findsNothing);
    });

    testWidgets('completes onboarding and closes dialog on start button tap', (
      WidgetTester tester,
    ) async {
      await showDialog(tester);

      for (int i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();

      // Dialog closed, home screen visible
      expect(find.text('comerune へようこそ'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(store.isCompleted(), isTrue);
    });

    testWidgets('displays page indicator with correct count', (
      WidgetTester tester,
    ) async {
      await showDialog(tester);

      expect(find.byType(AnimatedContainer), findsNWidgets(4));
    });

    testWidgets('cannot be dismissed by tapping barrier', (
      WidgetTester tester,
    ) async {
      await showDialog(tester);

      // Tap outside the dialog card
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Dialog is still showing
      expect(find.text('comerune へようこそ'), findsOneWidget);
    });
  });
}
