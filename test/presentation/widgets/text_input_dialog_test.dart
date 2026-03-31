import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/text_input_dialog.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildHarness({
  required String title,
  String? labelText,
  String? hintText,
  String? initialValue,
  String? cancelLabel,
  String? confirmLabel,
  Key? textFieldKey,
  Key? confirmButtonKey,
  required void Function(String?) onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext ctx) {
          return ElevatedButton(
            key: const Key('open-dialog'),
            onPressed: () async {
              final String? result = await showTextInputDialog(
                context: ctx,
                title: title,
                labelText: labelText,
                hintText: hintText,
                initialValue: initialValue,
                cancelLabel: cancelLabel ?? 'キャンセル',
                confirmLabel: confirmLabel ?? 'OK',
                textFieldKey: textFieldKey,
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
  group('showTextInputDialog', () {
    testWidgets('renders the dialog title', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(title: 'タイトルです', onResult: (_) {}),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('タイトルです'), findsOneWidget);
    });

    testWidgets('returns null when cancel button is tapped',
        (WidgetTester tester) async {
      String? captured = 'sentinel';

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          onResult: (String? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });

    testWidgets('returns trimmed text when OK is tapped',
        (WidgetTester tester) async {
      String? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          textFieldKey: const Key('input-field'),
          onResult: (String? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('input-field')), '  hello  ');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(captured, 'hello');
    });

    testWidgets('pre-fills the text field with initialValue',
        (WidgetTester tester) async {
      String? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          initialValue: 'pre-filled',
          textFieldKey: const Key('input-field'),
          onResult: (String? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      // The field should already contain the initial value.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('input-field')))
            .controller
            ?.text,
        'pre-filled',
      );

      // Confirm without editing — should return the initial value.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(captured, 'pre-filled');
    });

    testWidgets('uses custom cancel label', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          cancelLabel: 'とじる',
          onResult: (_) {},
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('とじる'), findsOneWidget);
      expect(find.text('キャンセル'), findsNothing);
    });

    testWidgets('uses custom confirm label', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          confirmLabel: '追加',
          onResult: (_) {},
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.text('追加'), findsOneWidget);
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('textFieldKey is applied to the TextField',
        (WidgetTester tester) async {
      const Key fieldKey = Key('special-text-field');

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          textFieldKey: fieldKey,
          onResult: (_) {},
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(fieldKey), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('confirmButtonKey is applied to the confirm button',
        (WidgetTester tester) async {
      const Key confirmKey = Key('my-confirm-btn');
      String? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          textFieldKey: const Key('f'),
          confirmButtonKey: confirmKey,
          onResult: (String? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(confirmKey), findsOneWidget);

      await tester.enterText(find.byKey(const Key('f')), 'hello');
      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();

      expect(captured, 'hello');
    });

    testWidgets('returns empty string when OK is tapped with blank input',
        (WidgetTester tester) async {
      String? captured = 'sentinel';

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          textFieldKey: const Key('f'),
          onResult: (String? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      // Field starts empty; tap OK without entering text.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // trim() of '' is still ''.
      expect(captured, '');
    });

    testWidgets('returns null when dialog is dismissed via barrier tap',
        (WidgetTester tester) async {
      String? captured = 'sentinel';

      await tester.pumpWidget(
        _buildHarness(
          title: 'T',
          onResult: (String? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });

    // -----------------------------------------------------------------------
    // Regression: favorite-user-id-input Key used in FavoriteUserListScreen
    // -----------------------------------------------------------------------
    testWidgets(
        'favorite-user-id-input Key resolves to the TextField in context',
        (WidgetTester tester) async {
      String? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: 'ユーザーID追加',
          hintText: 'ユーザーIDを入力',
          textFieldKey: const Key('favorite-user-id-input'),
          confirmButtonKey: const Key('favorite-add-confirm-button'),
          confirmLabel: '追加',
          onResult: (String? v) => captured = v,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('favorite-user-id-input')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('favorite-add-confirm-button')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('favorite-user-id-input')),
        '12345',
      );
      await tester.tap(find.byKey(const Key('favorite-add-confirm-button')));
      await tester.pumpAndSettle();

      expect(captured, '12345');
    });
  });
}
