import 'dart:async';

import 'package:comerune/application/comment_post/comment_post_controller.dart';
import 'package:comerune/data/comment/live_comment_repository.dart';
import 'package:comerune/presentation/widgets/comment_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommentInputBar (harness matches CommentScreen wiring)', () {
    testWidgets('renders nothing when not logged in', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: false,
        isBroadcaster: false,
        onSend: _successSend,
      );

      expect(find.byKey(const Key('comment-post-fab')), findsNothing);
      expect(find.byKey(const Key('comment-post-textfield')), findsNothing);
    });

    testWidgets('shows FAB when logged in', (WidgetTester tester) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );

      expect(find.byKey(const Key('comment-post-fab')), findsOneWidget);
      // Collapsed state does not show the textfield.
      expect(find.byKey(const Key('comment-post-textfield')), findsNothing);
    });

    testWidgets('FAB renders as a translucent circle with the pencil icon', (
      WidgetTester tester,
    ) async {
      // Pins the visual contract of the hand-rolled FAB so a future
      // refactor that drops e.g. `surfaceTintColor: Colors.transparent`
      // or changes the shape/alpha is caught by a red test.
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );

      final Finder fab = find.byKey(const Key('comment-post-fab'));
      expect(fab, findsOneWidget);

      // Material ancestor must be a circle, transparency-preserving, and
      // tinted with primary @ alpha 0.55.
      final Material material = tester.widget<Material>(
        find.ancestor(of: fab, matching: find.byType(Material)).first,
      );
      expect(material.shape, isA<CircleBorder>());
      expect(material.surfaceTintColor, Colors.transparent);
      final Color? mColor = material.color;
      expect(mColor, isNotNull);
      expect(mColor!.a, closeTo(0.55, 0.01));

      // Visual size 40x40, tap target 48x48.
      final Size visual = tester.getSize(
        find.ancestor(of: fab, matching: find.byType(Material)).first,
      );
      expect(visual, const Size(40, 40));
      final Size tapTarget = tester.getSize(
        find.ancestor(of: fab, matching: find.byType(Semantics)).last,
      );
      expect(tapTarget.width, greaterThanOrEqualTo(48));
      expect(tapTarget.height, greaterThanOrEqualTo(48));

      // Pencil icon.
      expect(
        find.descendant(of: fab, matching: find.byIcon(Icons.edit_outlined)),
        findsOneWidget,
      );
    });

    testWidgets('tapping FAB expands the input', (WidgetTester tester) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );

      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comment-post-textfield')), findsOneWidget);
      expect(find.byKey(const Key('comment-post-send-button')), findsOneWidget);
      expect(find.byKey(const Key('comment-post-fab')), findsNothing);
    });

    testWidgets('shows operator toggle only for broadcaster', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: true,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comment-post-operator-toggle')),
        findsOneWidget,
      );
    });

    testWidgets('hides operator toggle for viewer', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comment-post-operator-toggle')),
        findsNothing,
      );
    });

    testWidgets('send button is disabled when input is empty', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      final IconButton sendButton = tester.widget<IconButton>(
        find.byKey(const Key('comment-post-send-button')),
      );
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('send button enables once the user types valid text', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'hello',
      );
      await tester.pump();

      final IconButton sendButton = tester.widget<IconButton>(
        find.byKey(const Key('comment-post-send-button')),
      );
      expect(sendButton.onPressed, isNotNull);
    });

    testWidgets('send button disables when text exceeds normal limit', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'a' * 76,
      );
      await tester.pump();

      final IconButton sendButton = tester.widget<IconButton>(
        find.byKey(const Key('comment-post-send-button')),
      );
      expect(sendButton.onPressed, isNull);
    });

    testWidgets('counter shows current/max characters and turns red on over', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comment-post-counter')), findsOneWidget);
      expect(find.text('0 / 75'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'a' * 76,
      );
      await tester.pump();
      expect(find.text('76 / 75'), findsOneWidget);
    });

    testWidgets('successful send collapses the input back to FAB', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'hello',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('comment-post-send-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comment-post-fab')), findsOneWidget);
      expect(find.byKey(const Key('comment-post-textfield')), findsNothing);
    });

    testWidgets('Enter key submits a valid draft', (WidgetTester tester) async {
      int sendCount = 0;
      String? capturedText;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              sendCount++;
              capturedText = text;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'hi via enter',
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(sendCount, 1);
      expect(capturedText, 'hi via enter');
      // Successful send collapses the overlay back to the FAB.
      expect(find.byKey(const Key('comment-post-fab')), findsOneWidget);
    });

    testWidgets('Shift+Enter inserts a newline and does not submit', (
      WidgetTester tester,
    ) async {
      int sendCount = 0;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              sendCount++;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'line1',
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(sendCount, 0);
      // Input is still expanded because submit did not fire.
      expect(find.byKey(const Key('comment-post-textfield')), findsOneWidget);
    });

    testWidgets('Enter on empty draft does not submit', (
      WidgetTester tester,
    ) async {
      int sendCount = 0;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              sendCount++;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(sendCount, 0);
      expect(find.byKey(const Key('comment-post-textfield')), findsOneWidget);
    });

    testWidgets('Numpad Enter also submits the draft', (
      WidgetTester tester,
    ) async {
      int sendCount = 0;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              sendCount++;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'numpad',
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();

      expect(sendCount, 1);
    });

    testWidgets('Ctrl+Enter submits (non-Shift modifiers treated as submit)', (
      WidgetTester tester,
    ) async {
      // Pins the current behaviour: only Shift suppresses submit. Ctrl+Enter
      // and other modifier+Enter combinations intentionally submit so chat-app
      // muscle memory (Ctrl+Enter = send) works without a special case.
      int sendCount = 0;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              sendCount++;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'with ctrl',
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(sendCount, 1);
    });

    testWidgets(
      'Enter while a send is in-flight does not trigger a second send',
      (WidgetTester tester) async {
        // Pin defence-in-depth: even if the user hammers Enter while the
        // network is still resolving the first request, _canSendForValue
        // returns false and the key handler swallows the event.
        int sendCount = 0;
        final Completer<CommentSendResult> gate =
            Completer<CommentSendResult>();
        await _pump(
          tester,
          isLoggedIn: true,
          isBroadcaster: false,
          onSend:
              ({
                required String text,
                required bool asOperator,
                required int maxLength,
                required bool isAnonymous,
              }) {
                sendCount++;
                return gate.future;
              },
        );
        await tester.tap(find.byKey(const Key('comment-post-fab')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('comment-post-textfield')),
          'hammer',
        );
        await tester.pump();

        // First Enter starts the (pending) send.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(sendCount, 1);

        // Second Enter while the first is in flight must be ignored.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(sendCount, 1);

        // Release the gate so the widget can settle and the test tears
        // down cleanly.
        gate.complete(_successResult());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Enter submits multi-line drafts as a single payload', (
      WidgetTester tester,
    ) async {
      // Guards against a regression where the Shift+Enter newline path is
      // accidentally swallowed or the submit path strips the newline.
      String? capturedText;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              capturedText = text;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      // Simulate a two-line draft via enterText (covers the case where the
      // newline was inserted by the soft keyboard / IME). The Shift+Enter
      // keypath itself is covered by the adjacent test.
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'line1\nline2',
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(capturedText, 'line1\nline2');
      expect(find.byKey(const Key('comment-post-fab')), findsOneWidget);
    });

    testWidgets('failed send keeps the input expanded', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _failureSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'hello',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('comment-post-send-button')));
      await tester.pumpAndSettle();

      // Still expanded after a failure so the user can retry.
      expect(find.byKey(const Key('comment-post-textfield')), findsOneWidget);
    });

    testWidgets('toggle switches max length to 60 for operator mode', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: true,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      // Defaults to operator mode => limit is 100.
      expect(find.text('0 / 100'), findsOneWidget);

      // Toggle to normal mode.
      await tester.tap(find.byKey(const Key('comment-post-operator-toggle')));
      await tester.pump();

      expect(find.text('0 / 75'), findsOneWidget);
    });

    testWidgets('uses injected operatorMaxLength when provided', (
      WidgetTester tester,
    ) async {
      // Pin the operator limit to a deterministic sentinel (42) so the
      // assertion does not depend on the global constant. This also proves
      // the widget no longer reads the constant directly.
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: true,
        onSend: _successSend,
        operatorMaxLength: 42,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      expect(find.text('0 / 42'), findsOneWidget);
    });

    testWidgets(
      'send button respects injected operatorMaxLength at its boundary',
      (WidgetTester tester) async {
        await _pump(
          tester,
          isLoggedIn: true,
          isBroadcaster: true,
          onSend: _successSend,
          operatorMaxLength: 42,
        );
        await tester.tap(find.byKey(const Key('comment-post-fab')));
        await tester.pumpAndSettle();

        // Exactly 42 chars — must be allowed (boundary).
        await tester.enterText(
          find.byKey(const Key('comment-post-textfield')),
          'a' * 42,
        );
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('comment-post-send-button')),
              )
              .onPressed,
          isNotNull,
          reason: 'exactly at the injected limit should be sendable',
        );

        // 43 chars — must block.
        await tester.enterText(
          find.byKey(const Key('comment-post-textfield')),
          'a' * 43,
        );
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('comment-post-send-button')),
              )
              .onPressed,
          isNull,
          reason: 'one over the injected limit should be blocked',
        );
      },
    );

    testWidgets('injected maxLength is passed to the send callback', (
      WidgetTester tester,
    ) async {
      int? capturedMaxLength;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: true,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              capturedMaxLength = maxLength;
              return const CommentSendResult.posted(
                CommentPostResult(success: true),
              );
            },
        operatorMaxLength: 42,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'hi',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-post-send-button')));
      await tester.pumpAndSettle();

      // The widget must forward the same limit the UI enforced so that
      // the controller's validateText() agrees with the UI counter.
      expect(capturedMaxLength, 42);
    });

    testWidgets('constructor asserts reject non-positive max lengths', (
      WidgetTester tester,
    ) async {
      expect(
        () => CommentInputBar(
          isBroadcaster: false,
          onSend: _successSend,
          onCollapse: () {},
          normalMaxLength: 0,
        ),
        throwsAssertionError,
      );
      expect(
        () => CommentInputBar(
          isBroadcaster: true,
          onSend: _successSend,
          onCollapse: () {},
          operatorMaxLength: -1,
        ),
        throwsAssertionError,
      );
    });

    testWidgets('uses injected normalMaxLength when provided', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
        normalMaxLength: 17,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      expect(find.text('0 / 17'), findsOneWidget);
    });

    testWidgets(
      'flips to operator mode when isBroadcaster transitions false→true mid-session',
      (WidgetTester tester) async {
        // Bar mounts as a non-broadcaster (mirrors prod: broadcaster status
        // is resolved asynchronously after the FAB is tapped). Counter
        // shows the normal limit.
        final _BroadcasterToggleHarness harness = _BroadcasterToggleHarness(
          initialIsBroadcaster: false,
          onSend: _successSend,
        );
        await tester.pumpWidget(MaterialApp(home: harness));
        await tester.tap(find.byKey(const Key('comment-post-fab')));
        await tester.pumpAndSettle();
        expect(find.text('0 / 75'), findsOneWidget);
        expect(
          find.byKey(const Key('comment-post-operator-toggle')),
          findsNothing,
        );

        // Parent updates broadcaster flag → the bar must default to
        // operator mode per the Issue #123 spec, not stay on viewer mode.
        harness.setBroadcaster(true);
        await tester.pump();
        expect(find.text('0 / 100'), findsOneWidget);
        expect(
          find.byKey(const Key('comment-post-operator-toggle')),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows anonymous toggle for viewer (default 名札なし)', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comment-post-anonymous-toggle')),
        findsOneWidget,
      );
      // Default state is 名札なし (184), rendered as Icons.person_off.
      expect(
        find.descendant(
          of: find.byKey(const Key('comment-post-anonymous-toggle')),
          matching: find.byIcon(Icons.person_off),
        ),
        findsOneWidget,
      );
    });

    testWidgets('broadcaster + 通常 mode shows anonymous toggle', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: true,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      // Default for broadcaster is 運営; flip to 通常 first.
      await tester.tap(find.byKey(const Key('comment-post-operator-toggle')));
      await tester.pump();

      expect(
        find.byKey(const Key('comment-post-anonymous-toggle')),
        findsOneWidget,
      );
    });

    testWidgets('broadcaster + 運営 mode hides anonymous toggle', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: true,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      // Broadcaster defaults to 運営 mode → anonymous toggle must be hidden.
      expect(
        find.byKey(const Key('comment-post-anonymous-toggle')),
        findsNothing,
      );
    });

    testWidgets('tapping anonymous toggle swaps icon to person', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      final Finder toggle = find.byKey(
        const Key('comment-post-anonymous-toggle'),
      );
      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.person_off)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.person)),
        findsNothing,
      );

      await tester.tap(toggle);
      await tester.pump();

      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.person_off)),
        findsNothing,
      );
      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.person)),
        findsOneWidget,
      );
    });

    testWidgets('send forwards isAnonymous=true by default', (
      WidgetTester tester,
    ) async {
      bool? captured;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              captured = isAnonymous;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'hi',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-post-send-button')));
      await tester.pumpAndSettle();

      expect(captured, isTrue);
    });

    testWidgets('send forwards isAnonymous=false when toggled off', (
      WidgetTester tester,
    ) async {
      bool? captured;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              captured = isAnonymous;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-post-anonymous-toggle')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'hi',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-post-send-button')));
      await tester.pumpAndSettle();

      expect(captured, isFalse);
    });

    testWidgets(
      'switching broadcaster to 運営 resets anonymous selection to false',
      (WidgetTester tester) async {
        bool? captured;
        await _pump(
          tester,
          isLoggedIn: true,
          isBroadcaster: true,
          onSend:
              ({
                required String text,
                required bool asOperator,
                required int maxLength,
                required bool isAnonymous,
              }) async {
                captured = isAnonymous;
                return _successResult();
              },
        );
        await tester.tap(find.byKey(const Key('comment-post-fab')));
        await tester.pumpAndSettle();

        // Go to 通常 mode, turn anonymous off, then go back to 運営.
        await tester.tap(find.byKey(const Key('comment-post-operator-toggle')));
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('comment-post-anonymous-toggle')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('comment-post-operator-toggle')));
        await tester.pump();

        // Anonymous toggle must be hidden in 運営 mode.
        expect(
          find.byKey(const Key('comment-post-anonymous-toggle')),
          findsNothing,
        );

        // Flip back to 通常 — anonymous must be reset to false.
        await tester.tap(find.byKey(const Key('comment-post-operator-toggle')));
        await tester.pump();
        final Finder anonToggle = find.byKey(
          const Key('comment-post-anonymous-toggle'),
        );
        expect(
          find.descendant(of: anonToggle, matching: find.byIcon(Icons.person)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: anonToggle,
            matching: find.byIcon(Icons.person_off),
          ),
          findsNothing,
        );

        // And sending confirms it.
        await tester.enterText(
          find.byKey(const Key('comment-post-textfield')),
          'hi',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('comment-post-send-button')));
        await tester.pumpAndSettle();
        expect(captured, isFalse);
      },
    );

    testWidgets('operator comment never forwards isAnonymous=true', (
      WidgetTester tester,
    ) async {
      // Defence-in-depth: even if somehow the toggle state leaked, the send
      // method must clamp isAnonymous to false for operator posts.
      bool? captured;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: true,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              captured = isAnonymous;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();
      // Broadcaster defaults to 運営 mode.
      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'op',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment-post-send-button')));
      await tester.pumpAndSettle();
      expect(captured, isFalse);
    });

    testWidgets('anonymous toggle exposes Semantics(button, toggled)', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend: _successSend,
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      final Finder toggle = find.byKey(
        const Key('comment-post-anonymous-toggle'),
      );
      // Initial state: toggled=true (anonymous by default).
      final Finder semanticsBefore = find
          .ancestor(
            of: toggle,
            matching: find.byWidgetPredicate(
              (Widget w) => w is Semantics && (w.properties.button ?? false),
            ),
          )
          .first;
      final Semantics before = tester.widget<Semantics>(semanticsBefore);
      expect(before.properties.button, isTrue);
      expect(before.properties.toggled, isTrue);

      await tester.tap(toggle);
      await tester.pump();

      final Finder semanticsAfter = find
          .ancestor(
            of: toggle,
            matching: find.byWidgetPredicate(
              (Widget w) => w is Semantics && (w.properties.button ?? false),
            ),
          )
          .first;
      final Semantics after = tester.widget<Semantics>(semanticsAfter);
      expect(after.properties.toggled, isFalse);
    });

    testWidgets('close button collapses without sending', (
      WidgetTester tester,
    ) async {
      int sendCount = 0;
      await _pump(
        tester,
        isLoggedIn: true,
        isBroadcaster: false,
        onSend:
            ({
              required String text,
              required bool asOperator,
              required int maxLength,
              required bool isAnonymous,
            }) async {
              sendCount++;
              return _successResult();
            },
      );
      await tester.tap(find.byKey(const Key('comment-post-fab')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-post-textfield')),
        'draft',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('comment-post-close-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comment-post-fab')), findsOneWidget);
      expect(sendCount, 0);
    });
  });
}

/// Mounts a small harness that mirrors how `_CommentScreenState` composes
/// [CommentPostFab] + [CommentInputBar]: parent owns the expanded flag and
/// the login gate, the FAB opens the overlay, and a successful send closes
/// it via the overlay's `onCollapse` callback.
Future<void> _pump(
  WidgetTester tester, {
  required bool isLoggedIn,
  required bool isBroadcaster,
  required CommentSendCallback onSend,
  int? normalMaxLength,
  int? operatorMaxLength,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _Harness(
        isLoggedIn: isLoggedIn,
        isBroadcaster: isBroadcaster,
        onSend: onSend,
        normalMaxLength: normalMaxLength,
        operatorMaxLength: operatorMaxLength,
      ),
    ),
  );
}

/// Harness used by the broadcaster-flag transition test. Mounts the bar in
/// expanded state from the start (mirroring the production case where the
/// FAB is tapped before the async broadcaster check finishes), then lets
/// the test flip [isBroadcaster] via [setBroadcaster].
class _BroadcasterToggleHarness extends StatefulWidget {
  const _BroadcasterToggleHarness({
    required this.initialIsBroadcaster,
    required this.onSend,
  });

  final bool initialIsBroadcaster;
  final CommentSendCallback onSend;

  @override
  State<_BroadcasterToggleHarness> createState() =>
      _BroadcasterToggleHarnessState();

  void setBroadcaster(bool value) {
    final _BroadcasterToggleHarnessState? state =
        _BroadcasterToggleHarnessState._instance;
    state?._setBroadcaster(value);
  }
}

class _BroadcasterToggleHarnessState extends State<_BroadcasterToggleHarness> {
  static _BroadcasterToggleHarnessState? _instance;
  late bool _isBroadcaster;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _isBroadcaster = widget.initialIsBroadcaster;
    _instance = this;
  }

  @override
  void dispose() {
    if (_instance == this) {
      _instance = null;
    }
    super.dispose();
  }

  void _setBroadcaster(bool value) {
    if (!mounted) return;
    setState(() => _isBroadcaster = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          if (!_expanded)
            Positioned(
              right: 12,
              bottom: 12,
              child: CommentPostFab(
                onPressed: () => setState(() => _expanded = true),
              ),
            ),
          if (_expanded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CommentInputBar(
                isBroadcaster: _isBroadcaster,
                onSend: widget.onSend,
                onCollapse: () => setState(() => _expanded = false),
              ),
            ),
        ],
      ),
    );
  }
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.isLoggedIn,
    required this.isBroadcaster,
    required this.onSend,
    this.normalMaxLength,
    this.operatorMaxLength,
  });

  final bool isLoggedIn;
  final bool isBroadcaster;
  final CommentSendCallback onSend;
  final int? normalMaxLength;
  final int? operatorMaxLength;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          if (widget.isLoggedIn && !_expanded)
            Positioned(
              right: 12,
              bottom: 12,
              child: CommentPostFab(
                onPressed: () => setState(() => _expanded = true),
              ),
            ),
          if (_expanded)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CommentInputBar(
                isBroadcaster: widget.isBroadcaster,
                onSend: widget.onSend,
                onCollapse: () => setState(() => _expanded = false),
                normalMaxLength:
                    widget.normalMaxLength ?? kNormalCommentMaxLength,
                operatorMaxLength:
                    widget.operatorMaxLength ?? kOperatorCommentMaxLength,
              ),
            ),
        ],
      ),
    );
  }
}

CommentSendResult _successResult() {
  return const CommentSendResult.posted(CommentPostResult(success: true));
}

Future<CommentSendResult> _successSend({
  required String text,
  required bool asOperator,
  required int maxLength,
  required bool isAnonymous,
}) async {
  return _successResult();
}

Future<CommentSendResult> _failureSend({
  required String text,
  required bool asOperator,
  required int maxLength,
  required bool isAnonymous,
}) async {
  return const CommentSendResult.posted(
    CommentPostResult(
      success: false,
      errorCode: 'FORBIDDEN',
      errorMessage: 'nope',
    ),
  );
}
