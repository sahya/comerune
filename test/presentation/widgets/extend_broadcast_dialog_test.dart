import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/presentation/widgets/extend_broadcast_dialog.dart';

void main() {
  group('ExtendBroadcastDialog', () {
    testWidgets('renders all 6 fixed minute options', (
      WidgetTester tester,
    ) async {
      await _pumpDialog(tester, onConfirm: (int minutes) async => true);

      // Open the dropdown to inspect items in the overlay menu.
      await tester.tap(
        find.byKey(const Key('extend-broadcast-minutes-dropdown')),
      );
      await tester.pumpAndSettle();

      for (final int minutes in <int>[30, 60, 90, 120, 180, 210]) {
        expect(
          find.text('$minutes 分'),
          findsWidgets,
          reason: 'option for $minutes minutes must be present',
        );
      }
    });

    testWidgets('initial selection is 30 minutes', (WidgetTester tester) async {
      int? capturedMinutes;
      await _pumpDialog(
        tester,
        onConfirm: (int minutes) async {
          capturedMinutes = minutes;
          return true;
        },
      );

      // Without changing the dropdown, tap confirm — the callback must
      // receive 30 (the documented default).
      await tester.tap(
        find.byKey(const Key('extend-broadcast-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(capturedMinutes, 30);
    });

    testWidgets(
      'selecting a different option then confirming passes the chosen minutes',
      (WidgetTester tester) async {
        int? capturedMinutes;
        await _pumpDialog(
          tester,
          onConfirm: (int minutes) async {
            capturedMinutes = minutes;
            return true;
          },
        );

        await tester.tap(
          find.byKey(const Key('extend-broadcast-minutes-dropdown')),
        );
        await tester.pumpAndSettle();
        // When the dropdown is open, the option appears twice: once in the
        // closed dropdown's display row and once in the opened overlay.
        // `.last` picks the menu-overlay tile so the tap registers on the
        // selectable item, not on the still-rendered field display.
        await tester.tap(find.text('120 分').last);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('extend-broadcast-confirm-button')),
        );
        await tester.pumpAndSettle();

        expect(capturedMinutes, 120);
      },
    );

    testWidgets('cancel button dismisses with null result', (
      WidgetTester tester,
    ) async {
      ExtendBroadcastDialogResult? capturedOutcome;
      bool callbackInvoked = false;
      await _pumpDialog(
        tester,
        onConfirm: (int minutes) async {
          callbackInvoked = true;
          return true;
        },
        onClosed: (ExtendBroadcastDialogResult? outcome) {
          capturedOutcome = outcome;
        },
      );

      await tester.tap(find.byKey(const Key('extend-broadcast-cancel-button')));
      await tester.pumpAndSettle();

      expect(capturedOutcome, isNull);
      expect(callbackInvoked, isFalse);
    });

    testWidgets(
      'confirm shows progress and disables UI while onConfirm is pending',
      (WidgetTester tester) async {
        final Completer<bool> pending = Completer<bool>();
        await _pumpDialog(tester, onConfirm: (int minutes) => pending.future);

        await tester.tap(
          find.byKey(const Key('extend-broadcast-confirm-button')),
        );
        // Bounded pumps because CircularProgressIndicator never settles.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Spinner inside the confirm button.
        expect(
          find.descendant(
            of: find.byKey(const Key('extend-broadcast-confirm-button')),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );

        // Confirm button is disabled while pending.
        final FilledButton confirmButton = tester.widget(
          find.byKey(const Key('extend-broadcast-confirm-button')),
        );
        expect(confirmButton.onPressed, isNull);

        // Cancel button is also disabled.
        final TextButton cancelButton = tester.widget(
          find.byKey(const Key('extend-broadcast-cancel-button')),
        );
        expect(cancelButton.onPressed, isNull);

        // Dropdown is disabled (onChanged is null).
        final DropdownButtonFormField<int> dropdown = tester.widget(
          find.byKey(const Key('extend-broadcast-minutes-dropdown')),
        );
        expect(dropdown.onChanged, isNull);

        pending.complete(true);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('confirm with success returns success outcome', (
      WidgetTester tester,
    ) async {
      ExtendBroadcastDialogResult? capturedOutcome;
      await _pumpDialog(
        tester,
        onConfirm: (int minutes) async => true,
        onClosed: (ExtendBroadcastDialogResult? outcome) {
          capturedOutcome = outcome;
        },
      );

      await tester.tap(
        find.byKey(const Key('extend-broadcast-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(capturedOutcome, isNotNull);
      expect(capturedOutcome!.success, isTrue);
      expect(capturedOutcome!.minutes, 30);
    });

    testWidgets('confirm with failure returns failure outcome', (
      WidgetTester tester,
    ) async {
      ExtendBroadcastDialogResult? capturedOutcome;
      await _pumpDialog(
        tester,
        onConfirm: (int minutes) async => false,
        onClosed: (ExtendBroadcastDialogResult? outcome) {
          capturedOutcome = outcome;
        },
      );

      await tester.tap(
        find.byKey(const Key('extend-broadcast-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(capturedOutcome, isNotNull);
      expect(capturedOutcome!.success, isFalse);
      expect(capturedOutcome!.minutes, 30);
    });
  });
}

/// Mounts a button-triggered dialog so each test can interact with it
/// through the same finder keys. [onClosed] receives the dialog's result
/// (`null` on cancel) when the dialog tear-down completes.
Future<void> _pumpDialog(
  WidgetTester tester, {
  required ExtendBroadcastConfirmCallback onConfirm,
  void Function(ExtendBroadcastDialogResult? outcome)? onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            return Center(
              child: TextButton(
                key: const Key('open-dialog'),
                onPressed: () async {
                  final ExtendBroadcastDialogResult? outcome =
                      await showExtendBroadcastDialog(
                        context,
                        onConfirm: onConfirm,
                      );
                  onClosed?.call(outcome);
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-dialog')));
  await tester.pumpAndSettle();
}
