import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/confirm_dialog.dart';

Widget _buildHarness({
  required String title,
  required String content,
  String? cancelLabel,
  String? confirmLabel,
  Key? confirmButtonKey,
  required void Function(bool?) onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          return ElevatedButton(
            key: const Key('open-dialog'),
            onPressed: () async {
              final bool? result = await showConfirmDialog(
                context: context,
                title: title,
                content: content,
                cancelLabel: cancelLabel ?? 'キャンセル',
                confirmLabel: confirmLabel ?? '確認',
                confirmButtonKey: confirmButtonKey,
              );
              onResult(result);
            },
            child: const Text('open'),
          );
        },
      ),
    ),
  );
}

void main() {
  group('showConfirmDialog', () {
    testWidgets('shows title and content', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(title: 'タイトル', content: '本文', onResult: (_) {}),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('タイトル'), findsOneWidget);
      expect(find.text('本文'), findsOneWidget);
    });

    testWidgets('returns false on cancel', (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          onResult: (bool? result) => captured = result,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(captured, isFalse);
    });

    testWidgets('returns true on confirm', (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          onResult: (bool? result) => captured = result,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('確認'));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });

    testWidgets('applies custom confirm button key', (
      WidgetTester tester,
    ) async {
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          confirmButtonKey: const Key('favorite-remove-confirm-button'),
          onResult: (bool? result) => captured = result,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('favorite-remove-confirm-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('favorite-remove-confirm-button')));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });
  });
}
