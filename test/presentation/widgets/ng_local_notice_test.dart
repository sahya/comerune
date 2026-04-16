import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/ng_local_notice.dart';

void main() {
  group('NgLocalNotice', () {
    testWidgets('renders info icon with accessible semantic label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NgLocalNotice())),
      );

      final Finder iconFinder = find.byIcon(Icons.info_outline);
      expect(iconFinder, findsOneWidget);

      final Icon icon = tester.widget<Icon>(iconFinder);
      expect(icon.semanticLabel, 'NG設定の範囲のお知らせ');
    });

    testWidgets(
      'renders notice text clarifying no link with niconico service',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: NgLocalNotice())),
        );

        // Text is split across two string literals in source but rendered as
        // one continuous string; match on stable substrings.
        expect(find.textContaining('このアプリ内のコメントフィルタにのみ使われます'), findsOneWidget);
        expect(find.textContaining('ニコニコのサービスとは連携していません'), findsOneWidget);
      },
    );
  });
}
