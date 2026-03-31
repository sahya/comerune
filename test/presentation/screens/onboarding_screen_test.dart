import 'package:comerune/application/onboarding/onboarding_store.dart';
import 'package:comerune/presentation/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('OnboardingScreen', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesOnboardingStore store;
    late bool completed;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesOnboardingStore(prefs: prefs);
      completed = false;
    });

    Widget buildScreen() {
      return MaterialApp(
        home: OnboardingScreen(
          onboardingStore: store,
          onCompleted: () {
            completed = true;
          },
        ),
      );
    }

    testWidgets('shows welcome page on initial display', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('comerune へようこそ'), findsOneWidget);
      expect(find.text('つぎへ'), findsOneWidget);
    });

    testWidgets('navigates to next page on button tap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('つぎへ'));
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムでコメントを表示'), findsOneWidget);
    });

    testWidgets('navigates forward by swiping', (WidgetTester tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Swipe left to go to page 2
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('リアルタイムでコメントを表示'), findsOneWidget);
    });

    testWidgets('shows start button on last page', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Navigate to last page by swiping 3 times
      for (int i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
      }

      expect(find.text('準備完了！'), findsOneWidget);
      expect(find.text('はじめる'), findsOneWidget);
      expect(find.text('つぎへ'), findsNothing);
    });

    testWidgets('completes onboarding and marks store on start button tap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Navigate to last page
      for (int i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('はじめる'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(store.isCompleted(), isTrue);
    });

    testWidgets('displays page indicator with correct count', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // 4 page indicator dots rendered as AnimatedContainer
      expect(find.byType(AnimatedContainer), findsNWidgets(4));
    });
  });
}
