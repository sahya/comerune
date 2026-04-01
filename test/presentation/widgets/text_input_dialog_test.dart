import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/text_input_dialog.dart';

Widget _buildHarness({
  required String title,
  String? hintText,
  String? initialValue,
  String? clearButtonLabel,
  String? confirmLabel,
  Key? textFieldKey,
  Key? clearButtonKey,
  Key? confirmButtonKey,
  TextInputType? keyboardType,
  required void Function(String?) onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          return ElevatedButton(
            key: const Key('open-dialog'),
            onPressed: () async {
              final String? result = await showTextInputDialog(
                context: context,
                title: title,
                hintText: hintText,
                initialValue: initialValue,
                clearButtonLabel: clearButtonLabel,
                confirmLabel: confirmLabel ?? 'OK',
                textFieldKey: textFieldKey,
                clearButtonKey: clearButtonKey,
                confirmButtonKey: confirmButtonKey,
                keyboardType: keyboardType,
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
  group('showTextInputDialog', () {
    testWidgets('returns trimmed text on confirm', (WidgetTester tester) async {
      String? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: '入力',
          textFieldKey: const Key('favorite-user-id-input'),
          confirmButtonKey: const Key('favorite-add-confirm-button'),
          confirmLabel: '追加',
          onResult: (String? result) => captured = result,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('favorite-user-id-input')),
        '  12345  ',
      );
      await tester.tap(find.byKey(const Key('favorite-add-confirm-button')));
      await tester.pumpAndSettle();

      expect(captured, '12345');
    });

    testWidgets('returns null on cancel', (WidgetTester tester) async {
      String? captured = 'sentinel';

      await tester.pumpWidget(
        _buildHarness(
          title: '入力',
          onResult: (String? result) => captured = result,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });

    testWidgets('uses initialValue', (WidgetTester tester) async {
      String? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: '入力',
          initialValue: '初期値',
          textFieldKey: const Key('nickname-edit-field'),
          confirmButtonKey: const Key('nickname-edit-save-button'),
          confirmLabel: '保存',
          onResult: (String? result) => captured = result,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      final TextField textField = tester.widget(
        find.byKey(const Key('nickname-edit-field')),
      );
      expect(textField.controller?.text, '初期値');

      await tester.tap(find.byKey(const Key('nickname-edit-save-button')));
      await tester.pumpAndSettle();

      expect(captured, '初期値');
    });

    testWidgets('returns empty string on clear', (WidgetTester tester) async {
      String? captured;

      await tester.pumpWidget(
        _buildHarness(
          title: '入力',
          initialValue: '初期値',
          clearButtonLabel: 'クリア',
          clearButtonKey: const Key('nickname-edit-clear-button'),
          onResult: (String? result) => captured = result,
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nickname-edit-clear-button')));
      await tester.pumpAndSettle();

      expect(captured, '');
    });

    testWidgets('passes keyboardType to text field', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildHarness(
          title: '入力',
          keyboardType: TextInputType.number,
          textFieldKey: const Key('favorite-user-id-input'),
          onResult: (_) {},
        ),
      );

      await tester.tap(find.byKey(const Key('open-dialog')));
      await tester.pumpAndSettle();

      final TextField field = tester.widget(
        find.byKey(const Key('favorite-user-id-input')),
      );
      expect(field.keyboardType, TextInputType.number);
    });
  });
}
