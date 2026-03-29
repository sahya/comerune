import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/screens/comment_frequency_chart.dart';

void main() {
  group('CommentFrequencyChart', () {
    testWidgets('renders empty state when no data', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommentFrequencyChart(
              commentsPerMinute: <int, int>{},
            ),
          ),
        ),
      );

      expect(find.text('データなし'), findsOneWidget);
    });

    testWidgets('renders bars when data is provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommentFrequencyChart(
              commentsPerMinute: <int, int>{0: 5, 1: 10, 2: 3},
            ),
          ),
        ),
      );

      // Should find the CustomPaint widget used for bar rendering.
      expect(find.byType(CustomPaint), findsWidgets);
      // Should not show empty state.
      expect(find.text('データなし'), findsNothing);
    });

    testWidgets('calls onBarTapped when a bar area is tapped', (
      WidgetTester tester,
    ) async {
      int? tappedMinute;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentFrequencyChart(
              commentsPerMinute: const <int, int>{0: 5, 1: 10, 2: 3},
              onBarTapped: (int minute) => tappedMinute = minute,
            ),
          ),
        ),
      );

      // Tap on the chart area.
      final Finder gestureDetector = find.byType(GestureDetector);
      expect(gestureDetector, findsOneWidget);

      await tester.tapAt(tester.getCenter(gestureDetector));
      await tester.pumpAndSettle();

      expect(tappedMinute, isNotNull);
    });

    testWidgets('displays time axis labels', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CommentFrequencyChart(
              commentsPerMinute: <int, int>{0: 1, 15: 2, 30: 3},
            ),
          ),
        ),
      );

      expect(find.text('(分)'), findsOneWidget);
    });
  });
}
