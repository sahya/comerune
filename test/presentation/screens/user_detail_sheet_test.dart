import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/presentation/screens/user_detail_sheet.dart';

// ARGB32 value of kUserColorPalette.first (Color(0xFFE53935)).
const int _kFirstColorValue = 0xFFE53935;

// A color value that is intentionally outside of the preset palette.
const int _kCustomColorValue = 0xFF123456;

void main() {
  group('UserDetailSheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('displays user ID and resolved name', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          resolvedUserName: 'テストさん',
          allMessages: const <AppMessage>[],
        ),
      );
      await openSheet(tester);

      expect(find.text('ID: 12345'), findsOneWidget);
      expect(find.text('名前: テストさん'), findsOneWidget);
    });

    testWidgets('hides name when resolvedUserName is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(userId: '99999', allMessages: const <AppMessage>[]),
      );
      await openSheet(tester);

      expect(find.text('ID: 99999'), findsOneWidget);
      expect(find.byKey(const Key('user-detail-name')), findsNothing);
    });

    testWidgets('shows no-comments message when user has no comments', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(userId: '12345', allMessages: const <AppMessage>[]),
      );
      await openSheet(tester);

      expect(find.text('この放送でのコメントはありません'), findsOneWidget);
    });

    testWidgets('shows comment list filtered by user ID', (
      WidgetTester tester,
    ) async {
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '12345',
          content: 'hello',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'msg-2',
          timestamp: DateTime(2026, 3, 22, 12, 1, 0),
          userId: '99999',
          content: 'other user',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'msg-3',
          timestamp: DateTime(2026, 3, 22, 12, 2, 0),
          userId: '12345',
          content: 'world',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildSheet(userId: '12345', allMessages: messages),
      );
      await openSheet(tester);

      expect(find.textContaining('コメント履歴（2件）'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
      expect(find.text('other user'), findsNothing);
    });

    testWidgets('shows NG登録 button when user is not NG', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          isNgUser: false,
        ),
      );
      await openSheet(tester);

      expect(find.text('NG登録'), findsOneWidget);
    });

    testWidgets('shows NG解除 button when user is NG', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          isNgUser: true,
        ),
      );
      await openSheet(tester);

      expect(find.text('NG解除'), findsOneWidget);
    });

    testWidgets('onToggleNgUser is called when NG button is tapped', (
      WidgetTester tester,
    ) async {
      int toggleCount = 0;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onToggleNgUser: () {
            toggleCount += 1;
          },
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('ng-user-toggle-button')));
      await tester.pumpAndSettle();

      expect(toggleCount, 1);
    });

    testWidgets('shows color palette when onColorChanged is provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      expect(find.text('コメント色'), findsOneWidget);
      expect(find.byKey(const Key('user-color-palette')), findsOneWidget);
    });

    testWidgets('hides color palette when onColorChanged is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(userId: '12345', allMessages: const <AppMessage>[]),
      );
      await openSheet(tester);

      expect(find.text('コメント色'), findsNothing);
      expect(find.byKey(const Key('user-color-palette')), findsNothing);
    });

    testWidgets('tapping a color calls onColorChanged', (
      WidgetTester tester,
    ) async {
      int? selectedColor;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (int value) {
            selectedColor = value;
          },
        ),
      );
      await openSheet(tester);

      // Tap the first color in the palette.
      const int firstColorValue = _kFirstColorValue;
      await tester.tap(find.byKey(const Key('user-color-$firstColorValue')));
      await tester.pumpAndSettle();

      expect(selectedColor, firstColorValue);
    });

    testWidgets('shows reset button when currentColorValue is set', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          currentColorValue: _kFirstColorValue,
          onColorChanged: (_) {},
          onColorRemoved: () {},
        ),
      );
      await openSheet(tester);

      expect(find.text('リセット'), findsOneWidget);
    });

    testWidgets('hides reset button when currentColorValue is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      expect(find.text('リセット'), findsNothing);
    });

    testWidgets('shows custom color button when palette is visible', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      expect(find.byKey(const Key('user-color-custom-button')), findsOneWidget);
    });

    testWidgets('tapping custom color button shows color picker dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-custom-button')));
      await tester.pumpAndSettle();

      expect(find.text('カスタムカラー'), findsOneWidget);
      expect(find.byType(ColorPicker), findsOneWidget);
      expect(find.text('適用'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
    });

    testWidgets('cancel on custom dialog does not call onColorChanged', (
      WidgetTester tester,
    ) async {
      int callCount = 0;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {
            callCount += 1;
          },
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-custom-button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('user-color-custom-dialog-cancel-button')),
      );
      await tester.pumpAndSettle();

      expect(callCount, 0);
    });

    testWidgets(
      'apply on custom dialog calls onColorChanged with picked color',
      (WidgetTester tester) async {
        int? selectedColor;

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            // Start with a preset color so the dialog opens with that color.
            currentColorValue: _kFirstColorValue,
            onColorChanged: (int value) {
              selectedColor = value;
            },
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        // Apply without changing the color: onColorChanged should be called
        // with the initial (preset) color value, confirming the apply path.
        await tester.tap(
          find.byKey(const Key('user-color-custom-dialog-apply-button')),
        );
        await tester.pumpAndSettle();

        expect(selectedColor, _kFirstColorValue);
      },
    );

    testWidgets(
      'apply forwards the latest color from picker.onColorChanged callback',
      (WidgetTester tester) async {
        int? selectedColor;

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kFirstColorValue,
            onColorChanged: (int value) {
              selectedColor = value;
            },
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        // Drive the ColorPicker's onColorChanged callback directly to
        // simulate the user picking a color inside the wheel without
        // depending on the picker's internal slider/touch implementation.
        final ColorPicker picker = tester.widget<ColorPicker>(
          find.byType(ColorPicker),
        );
        picker.onColorChanged(const Color(_kCustomColorValue));

        await tester.tap(
          find.byKey(const Key('user-color-custom-dialog-apply-button')),
        );
        await tester.pumpAndSettle();

        expect(selectedColor, _kCustomColorValue);
      },
    );

    testWidgets(
      'reopening dialog with a custom color initializes picker with that color',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kCustomColorValue,
            onColorChanged: (_) {},
            onColorRemoved: () {},
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        final ColorPicker picker = tester.widget<ColorPicker>(
          find.byType(ColorPicker),
        );
        expect(picker.pickerColor, const Color(_kCustomColorValue));
      },
    );

    testWidgets(
      'custom color button shows check mark when current color is not a preset',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kCustomColorValue,
            onColorChanged: (_) {},
            onColorRemoved: () {},
          ),
        );
        await openSheet(tester);

        final Finder customButton = find.byKey(
          const Key('user-color-custom-button'),
        );
        expect(customButton, findsOneWidget);

        // When a custom (non-preset) color is selected, the button shows a
        // check icon. When no custom color is selected, it shows an add icon.
        expect(
          find.descendant(of: customButton, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: customButton, matching: find.byIcon(Icons.add)),
          findsNothing,
        );
      },
    );

    testWidgets(
      'custom color button shows add icon when current color is a preset',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kFirstColorValue,
            onColorChanged: (_) {},
            onColorRemoved: () {},
          ),
        );
        await openSheet(tester);

        final Finder customButton = find.byKey(
          const Key('user-color-custom-button'),
        );
        expect(
          find.descendant(of: customButton, matching: find.byIcon(Icons.add)),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'preset color tap still works with custom button present (regression)',
      (WidgetTester tester) async {
        int? selectedColor;

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            onColorChanged: (int value) {
              selectedColor = value;
            },
          ),
        );
        await openSheet(tester);

        const int firstColorValue = _kFirstColorValue;
        await tester.tap(find.byKey(const Key('user-color-$firstColorValue')));
        await tester.pumpAndSettle();

        expect(selectedColor, firstColorValue);
      },
    );

    testWidgets('preset color buttons expose a 48x48 hit target (a11y)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      // The visible circle is 32dp but the wrapping hit target should be
      // exactly 48dp on each side (Material / WCAG min target). Check
      // both a preset circle and the custom-color button.
      final Size presetSize = tester.getSize(
        find.byKey(const Key('user-color-$_kFirstColorValue')),
      );
      expect(presetSize.width, 48);
      expect(presetSize.height, 48);

      final Size customSize = tester.getSize(
        find.byKey(const Key('user-color-custom-button')),
      );
      expect(customSize.width, 48);
      expect(customSize.height, 48);
    });

    testWidgets(
      'adjacent preset color buttons do not overlap their hit targets (#777 AC4)',
      (WidgetTester tester) async {
        // Pin the viewport so the Wrap layout is deterministic regardless
        // of the host machine's default test screen size. With horizontal
        // 16dp padding on the palette row, the inner width is 800-32=768dp,
        // which fits 768/48=16 buttons per row. The palette has 12 preset
        // circles + 1 custom button (13 total), so all entries land on a
        // single row and adjacent pairs share the same vertical position.
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            onColorChanged: (_) {},
          ),
        );
        await openSheet(tester);

        // Walk the preset palette in declaration order and assert that
        // each pair of consecutive 48x48 hit-target boxes is strictly
        // non-overlapping. Same-row neighbours have matching `top`, and
        // their horizontal bounds must not overlap (`right <= next.left`).
        // Wrap row breaks (when they happen) are also acceptable: the
        // next button moves to a new row with `top >= previous.bottom`.
        const List<int> paletteValues = <int>[
          0xFFE53935,
          0xFFD81B60,
          0xFF8E24AA,
          0xFF3949AB,
          0xFF1E88E5,
          0xFF00ACC1,
          0xFF00897B,
          0xFF43A047,
          0xFFFF8F00,
          0xFFFF6D00,
          0xFF6D4C41,
          0xFF546E7A,
        ];

        Rect rectFor(int colorValue) =>
            tester.getRect(find.byKey(Key('user-color-$colorValue')));

        // Sanity: at the chosen viewport every preset circle shares the
        // same `top`, so neighbours are guaranteed to be on one row and
        // the right/left comparison is the load-bearing check.
        final double firstTop = rectFor(paletteValues.first).top;
        for (final int value in paletteValues) {
          expect(
            rectFor(value).top,
            firstTop,
            reason:
                'Preset color $value should be on the same row as the '
                'first preset at viewport 800x1200; if this fails the '
                'viewport assumption (768dp inner width / 13 buttons) '
                'is wrong.',
          );
        }

        for (int i = 0; i < paletteValues.length - 1; i++) {
          final Rect current = rectFor(paletteValues[i]);
          final Rect next = rectFor(paletteValues[i + 1]);
          final bool sameRow = current.top == next.top;
          if (sameRow) {
            expect(
              current.right <= next.left,
              isTrue,
              reason:
                  'Hit targets for ${paletteValues[i].toRadixString(16)} '
                  '(right=${current.right}) and '
                  '${paletteValues[i + 1].toRadixString(16)} '
                  '(left=${next.left}) overlap on the same row.',
            );
          } else {
            expect(
              current.bottom <= next.top,
              isTrue,
              reason:
                  'Hit targets for ${paletteValues[i].toRadixString(16)} '
                  '(bottom=${current.bottom}) and '
                  '${paletteValues[i + 1].toRadixString(16)} '
                  '(top=${next.top}) overlap across rows.',
            );
          }
        }

        // Also verify the boundary between the last preset and the
        // custom-color button, since they live in the same Wrap.
        final Rect lastPreset = rectFor(paletteValues.last);
        final Rect customButton = tester.getRect(
          find.byKey(const Key('user-color-custom-button')),
        );
        if (lastPreset.top == customButton.top) {
          expect(
            lastPreset.right <= customButton.left,
            isTrue,
            reason:
                'Last preset and custom-color button overlap on the same row '
                '(${lastPreset.right} > ${customButton.left}).',
          );
        } else {
          expect(
            lastPreset.bottom <= customButton.top,
            isTrue,
            reason:
                'Last preset and custom-color button overlap across rows '
                '(${lastPreset.bottom} > ${customButton.top}).',
          );
        }
      },
    );

    testWidgets('custom color dialog shows a Hex input field (#779)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-custom-button')));
      await tester.pumpAndSettle();

      // hexInputBar:true causes the package to render its
      // ColorPickerInput row, which contains a TextField. We don't rely
      // on the package's internal class name, only that an editable
      // TextField is present inside the dialog.
      expect(find.byType(ColorPicker), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets(
      'typing a valid Hex into the dialog input is accepted by the picker and apply forwards it (#779 AC2/AC4)',
      (WidgetTester tester) async {
        int? selectedColor;

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            currentColorValue: _kFirstColorValue,
            onColorChanged: (int value) {
              selectedColor = value;
            },
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        // Type a valid hex (without #) into the package's hex bar text
        // field. The package's internal hex input synchronously parses
        // valid hex strings and forwards the resulting Color through the
        // ColorPicker.onColorChanged callback, which our dialog stores in
        // the closure-captured `picked` variable. Applying afterwards
        // must forward that color to the host onColorChanged.
        final Finder hexField = find.byType(TextField).last;
        await tester.enterText(hexField, '112233');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('user-color-custom-dialog-apply-button')),
        );
        await tester.pumpAndSettle();

        // The host should have received the typed Hex (#112233) as ARGB32.
        expect(selectedColor, 0xFF112233);
      },
    );

    testWidgets('invalid Hex input does not crash the dialog (#779 AC3)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          onColorChanged: (_) {},
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-custom-button')));
      await tester.pumpAndSettle();

      // Type a clearly invalid hex into the field. The package validates
      // input internally and ignores malformed strings, so no exception
      // should escape and the dialog should remain open and usable.
      final Finder hexField = find.byType(TextField).last;
      await tester.enterText(hexField, 'ZZZZZZ');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ColorPicker), findsOneWidget);
      // Apply / Cancel buttons should still be usable.
      expect(
        find.byKey(const Key('user-color-custom-dialog-cancel-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('user-color-custom-dialog-apply-button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'small phone (360dp) is unaffected by the dialog max width (#780 AC3)',
      (WidgetTester tester) async {
        // 360dp wide phone — well below the 420dp cap, so the cap should
        // never kick in and the picker simply uses the available width.
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            onColorChanged: (_) {},
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        // Picker must still be visible and not zero-sized.
        final Size pickerSize = tester.getSize(find.byType(ColorPicker));
        expect(pickerSize.width, greaterThan(0));
        expect(pickerSize.width, lessThanOrEqualTo(360.0));
      },
    );

    testWidgets(
      'custom color dialog content is capped to the configured max width on large screens (#780)',
      (WidgetTester tester) async {
        // Simulate a tablet / landscape viewport that is wider than the
        // configured cap (420dp).
        await tester.binding.setSurfaceSize(const Size(1024, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildSheet(
            userId: '12345',
            allMessages: const <AppMessage>[],
            onColorChanged: (_) {},
          ),
        );
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('user-color-custom-button')));
        await tester.pumpAndSettle();

        // The ColorPicker is laid out inside our ConstrainedBox. Its
        // rendered width must therefore not exceed the cap (420dp), even
        // though the surrounding viewport is much wider.
        final Size pickerSize = tester.getSize(find.byType(ColorPicker));
        expect(pickerSize.width, lessThanOrEqualTo(420.0));
      },
    );

    testWidgets('tapping reset calls onColorRemoved', (
      WidgetTester tester,
    ) async {
      bool removeCalled = false;

      await tester.pumpWidget(
        _buildSheet(
          userId: '12345',
          allMessages: const <AppMessage>[],
          currentColorValue: _kFirstColorValue,
          onColorChanged: (_) {},
          onColorRemoved: () {
            removeCalled = true;
          },
        ),
      );
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('user-color-reset-button')));
      await tester.pumpAndSettle();

      expect(removeCalled, isTrue);
    });
  });
}

Widget _buildSheet({
  required String userId,
  String? resolvedUserName,
  required List<AppMessage> allMessages,
  bool isNgUser = false,
  VoidCallback? onToggleNgUser,
  int? currentColorValue,
  void Function(int)? onColorChanged,
  VoidCallback? onColorRemoved,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          return ElevatedButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => UserDetailSheet(
                  userId: userId,
                  resolvedUserName: resolvedUserName,
                  allMessages: allMessages,
                  isNgUser: isNgUser,
                  onToggleNgUser: onToggleNgUser ?? () {},
                  currentColorValue: currentColorValue,
                  onColorChanged: onColorChanged,
                  onColorRemoved: onColorRemoved,
                ),
              );
            },
            child: const Text('open'),
          );
        },
      ),
    ),
  );
}
