import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/confirm_dialog.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps a builder that opens [showConfirmDialog] via a button tap so that
/// the dialog has a valid [BuildContext] with a [Navigator].
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
        builder: (BuildContext ctx) {
          return ElevatedButton(
            key: const Key('open-dialog'),
            onPressed: () async {
              final bool? result = await showConfirmDialog(
                context: ctx,
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('showConfirmDialog', () {
    testWidgets('renders title and content text', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(
          title: 'タイトル',
          content: '本文テキスト',
          onResult: (_) {},
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('タイトル'), findsOneWidget);
      expect(find.text('本文テキスト'), findsOneWidget);
    });

    testWidgets('returns false when cancel button is tapped',
        (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          onResult: (bool? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(captured, isFalse);
    });

    testWidgets('returns true when confirm button is tapped',
        (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          onResult: (bool? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('確認'));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });

    testWidgets('uses custom cancel label', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          cancelLabel: 'やめる',
          onResult: (_) {},
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('やめる'), findsOneWidget);
      expect(find.text('キャンセル'), findsNothing);
    });

    testWidgets('uses custom confirm label', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          confirmLabel: '解除',
          onResult: (_) {},
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('解除'), findsOneWidget);
      expect(find.text('確認'), findsNothing);
    });

    testWidgets('applies custom Key to confirm button',
        (WidgetTester tester) async {
      const Key customKey = Key('my-confirm-key');
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          confirmButtonKey: customKey,
          onResult: (bool? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      // The key must exist and be tappable.
      expect(find.byKey(customKey), findsOneWidget);

      await tester.tap(find.byKey(customKey));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });

    testWidgets('returns null when dialog is dismissed via barrier tap',
        (WidgetTester tester) async {
      bool? captured = true; // intentional non-null starting value

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          content: 'C',
          onResult: (bool? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      // Tap outside the dialog to dismiss it.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });

    // -----------------------------------------------------------------------
    // Regression: ng-remove-confirm-button Key used in NgUserListScreen
    // -----------------------------------------------------------------------
    testWidgets('ng-remove-confirm-button Key resolves to the confirm button',
        (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'NG解除',
          content: 'ユーザーID「user123」のNG登録を解除しますか？',
          confirmLabel: '解除',
          confirmButtonKey: const Key('ng-remove-confirm-button'),
          onResult: (bool? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ng-remove-confirm-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ng-remove-confirm-button')));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });

    // -----------------------------------------------------------------------
    // Regression: favorite-remove-confirm-button Key used in FavoriteUserListScreen
    // -----------------------------------------------------------------------
    testWidgets(
        'favorite-remove-confirm-button Key resolves to the confirm button',
        (WidgetTester tester) async {
      bool? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'ユーザー削除',
          content: 'テストユーザー (12345) を削除しますか？',
          confirmLabel: '削除',
          confirmButtonKey: const Key('favorite-remove-confirm-button'),
          onResult: (bool? v) => captured = v,
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
