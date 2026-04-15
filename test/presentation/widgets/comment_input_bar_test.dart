import 'package:comerune/application/comment_post/comment_post_controller.dart';
import 'package:comerune/data/comment/live_comment_repository.dart';
import 'package:comerune/presentation/widgets/comment_input_bar.dart';
import 'package:flutter/material.dart';
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

    testWidgets('shows anonymous toggle for viewer (default 名札付き)', (
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
      // Default copy: 名札付き (icon: Icons.person).
      expect(find.text('名札付き'), findsOneWidget);
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

    testWidgets('tapping anonymous toggle swaps label to 名札なし', (
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

      expect(find.text('名札付き'), findsOneWidget);
      expect(find.text('名札なし'), findsNothing);

      await tester.tap(find.byKey(const Key('comment-post-anonymous-toggle')));
      await tester.pump();

      expect(find.text('名札付き'), findsNothing);
      expect(find.text('名札なし'), findsOneWidget);
    });

    testWidgets('send forwards isAnonymous=false by default', (
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

      expect(captured, isFalse);
    });

    testWidgets('send forwards isAnonymous=true when toggled on', (
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

      expect(captured, isTrue);
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

        // Go to 通常 mode, turn anonymous on, then go back to 運営.
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
        expect(find.text('名札付き'), findsOneWidget);
        expect(find.text('名札なし'), findsNothing);

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
      // Initial state: toggled=false.
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
      expect(before.properties.toggled, isFalse);

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
      expect(after.properties.toggled, isTrue);
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
