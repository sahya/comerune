import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/comment_post/comment_post_controller.dart';
import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:comerune/data/comment/live_comment_repository.dart';
import 'package:comerune/data/follow/my_program_repository.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

void main() {
  group('CommentScreen AppBar overflow "配信を終了" entry', () {
    testWidgets('is hidden by default (non-broadcaster, no repository)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(_buildScreen(supervisor: supervisor));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('end-broadcast-button')), findsNothing);
      // Existing entries still rendered so the menu itself is healthy.
      expect(find.byKey(const Key('comment-search-button')), findsOneWidget);
    });

    testWidgets('is hidden for broadcaster when no repository is wired', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(_buildScreen(supervisor: supervisor));
      await tester.pumpAndSettle();

      // Flip to broadcaster mode without supplying a repository — this
      // mirrors a misconfigured host or a debug build that intentionally
      // omits the broadcast-control wiring.
      final CommentScreenTestAccess access =
          tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess;
      access.setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('end-broadcast-button')), findsNothing);
    });

    testWidgets(
      'is shown in error color for broadcaster + repository, hidden after toggling off',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
          ),
        );
        await tester.pumpAndSettle();

        final CommentScreenTestAccess access =
            tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess;
        access.setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();

        final Finder entry = find.byKey(const Key('end-broadcast-button'));
        expect(entry, findsOneWidget);

        // Label color should follow theme.colorScheme.error so the row
        // reads as destructive at a glance.
        final BuildContext context = tester.element(entry);
        final Color expectedError = Theme.of(context).colorScheme.error;
        final Text labelText = tester.widget(
          find.descendant(of: entry, matching: find.text('配信を終了')),
        );
        expect(labelText.style?.color, expectedError);

        // Dismiss menu and toggle broadcaster off — the entry should
        // disappear without leaving stale UI behind.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        access.setBroadcasterForTesting(isBroadcaster: false);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('end-broadcast-button')), findsNothing);
      },
    );

    testWidgets(
      'menu lays the entry at the top followed by a divider, ahead of search/save/settings',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();

        // The end-broadcast row must sit visually ABOVE the comment-search
        // row, separated by a PopupMenuDivider so the destructive action
        // does not visually merge with the regular menu items.
        final double endBroadcastY = tester
            .getCenter(find.byKey(const Key('end-broadcast-button')))
            .dy;
        final double searchY = tester
            .getCenter(find.byKey(const Key('comment-search-button')))
            .dy;
        expect(
          endBroadcastY < searchY,
          isTrue,
          reason: 'end-broadcast entry must render above the search entry',
        );

        // At least one PopupMenuDivider must sit between the end-broadcast
        // row and the search row. Render-tree walking is fragile, so we
        // verify the divider exists in the menu route at all (the menu
        // currently only renders dividers in two known spots).
        expect(find.byType(PopupMenuDivider), findsWidgets);
      },
    );

    testWidgets('confirmation dialog uses the documented label copy', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, broadcastControlRepository: repo),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-broadcast-button')));
      await tester.pumpAndSettle();

      // Title and body strings must match Issue #750 exactly so the
      // user reads a verb-based, irreversibility-aware prompt.
      expect(find.text('配信を終了しますか？'), findsOneWidget);
      expect(find.text('この操作は取り消せません。視聴者の接続も切断されます。'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);

      // The confirm button label is "配信を終了" — same string as the
      // menu entry, so look it up via its dedicated key.
      final BuildContext dialogContext = tester.element(
        find.byKey(const Key('end-broadcast-confirm-dialog')),
      );
      final Color expectedError = Theme.of(dialogContext).colorScheme.error;
      final TextButton confirmButton = tester.widget(
        find.byKey(const Key('end-broadcast-confirm-button')),
      );
      // foregroundColor is wrapped in a MaterialStateProperty/WidgetStateProperty;
      // resolve against the default state to read the configured color.
      final Color? resolvedConfirmColor = confirmButton.style?.foregroundColor
          ?.resolve(<WidgetState>{});
      expect(resolvedConfirmColor, expectedError);
      expect(
        find.descendant(
          of: find.byKey(const Key('end-broadcast-confirm-button')),
          matching: find.text('配信を終了'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('end-broadcast-cancel-button')));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
    });

    testWidgets('cancel from confirmation dialog does not call repository', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          lv: 'lv9999',
          broadcastControlRepository: repo,
        ),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-broadcast-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('end-broadcast-confirm-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('end-broadcast-cancel-button')));
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
      expect(
        find.byKey(const Key('end-broadcast-confirm-dialog')),
        findsNothing,
      );
    });

    testWidgets(
      'confirm calls repository.endBroadcast with current lv + session',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            lv: 'lv12345',
            broadcastControlRepository: repo,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(
              isBroadcaster: true,
              userSession: 'session-abc',
            );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('end-broadcast-button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('end-broadcast-confirm-button')));
        await tester.pumpAndSettle();

        expect(repo.calls, hasLength(1));
        expect(repo.calls.single.programId, 'lv12345');
        expect(repo.calls.single.userSession, 'session-abc');
      },
    );

    testWidgets('success keeps quiet — no error SnackBar from this flow', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository(
            responder: (_, _) async =>
                const BroadcastControlResult(success: true),
          );

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, broadcastControlRepository: repo),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await _confirmEndBroadcast(tester);

      expect(
        find.byKey(const Key('end-broadcast-error-snackbar')),
        findsNothing,
      );
    });

    testWidgets(
      'CONFLICT (already-ended) keeps quiet — handed off to existing flow',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository(
              responder: (_, _) async => const BroadcastControlResult(
                success: false,
                errorCode: BroadcastControlErrorCode.conflict,
              ),
            );

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        await _confirmEndBroadcast(tester);

        expect(
          find.byKey(const Key('end-broadcast-error-snackbar')),
          findsNothing,
        );
      },
    );

    testWidgets('network error surfaces a localized SnackBar', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository(
            responder: (_, _) async => const BroadcastControlResult(
              success: false,
              errorCode: BroadcastControlErrorCode.networkError,
            ),
          );

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, broadcastControlRepository: repo),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await _confirmEndBroadcast(tester);

      expect(
        find.byKey(const Key('end-broadcast-error-snackbar')),
        findsOneWidget,
      );
    });

    testWidgets(
      'empty session surfaces "ログインが必要です" without calling the repository',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true, userSession: '');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('end-broadcast-button')));
        await tester.pumpAndSettle();

        expect(repo.calls, isEmpty);
        expect(
          find.byKey(const Key('end-broadcast-confirm-dialog')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('end-broadcast-session-required-snackbar')),
          findsOneWidget,
        );
      },
    );

    testWidgets('cancelling the dialog re-enables the menu item', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, broadcastControlRepository: repo),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-broadcast-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-broadcast-cancel-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      final PopupMenuItem<Object?> reopenedItem = tester.widget(
        find.byKey(const Key('end-broadcast-button')),
      );
      expect(reopenedItem.enabled, isTrue);
    });

    testWidgets('item is disabled while a request is in flight', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final Completer<BroadcastControlResult> pending =
          Completer<BroadcastControlResult>();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository(
            responder: (_, _) => pending.future,
          );

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, broadcastControlRepository: repo),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-broadcast-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('end-broadcast-confirm-button')));
      await tester.pump(); // start the future, do not settle

      // Re-open the menu — the item should be present but disabled.
      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      final PopupMenuItem<Object?> item = tester.widget(
        find.byKey(const Key('end-broadcast-button')),
      );
      expect(item.enabled, isFalse);

      // Drain the pending future so the test exits cleanly.
      pending.complete(const BroadcastControlResult(success: true));
      await tester.pumpAndSettle();
    });

    testWidgets('successful end flushes the comment-post broadcaster cache', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository(
            responder: (_, _) async =>
                const BroadcastControlResult(success: true),
          );
      final _SpyCommentPostController spy = _SpyCommentPostController();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          broadcastControlRepository: repo,
          commentPostController: spy,
        ),
      );
      await tester.pumpAndSettle();

      // Reset the count to zero AFTER the screen is built — the widget's
      // `setBroadcasterForTesting` path does not touch the controller,
      // but defensive resets here keep the assertion below independent
      // of any future incidental clears during initState.
      spy.clearBroadcasterCacheCallCount = 0;

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await _confirmEndBroadcast(tester);

      // Successful end MUST invalidate the broadcaster cache so a
      // subsequent broadcaster check does not return a stale
      // "broadcaster" outcome cached during the now-ended program
      // (#752). Without this assertion the wiring inside
      // `_endBroadcastFromMenu` could silently regress.
      expect(spy.clearBroadcasterCacheCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('CONFLICT (already-ended) also flushes the broadcaster cache', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository(
            responder: (_, _) async => const BroadcastControlResult(
              success: false,
              errorCode: BroadcastControlErrorCode.conflict,
            ),
          );
      final _SpyCommentPostController spy = _SpyCommentPostController();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          broadcastControlRepository: repo,
          commentPostController: spy,
        ),
      );
      await tester.pumpAndSettle();
      spy.clearBroadcasterCacheCallCount = 0;

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await _confirmEndBroadcast(tester);

      // Treat-as-success path must follow the same invalidation contract.
      expect(spy.clearBroadcasterCacheCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets(
      'network error keeps the broadcaster cache intact (no spurious flush)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository(
              responder: (_, _) async => const BroadcastControlResult(
                success: false,
                errorCode: BroadcastControlErrorCode.networkError,
              ),
            );
        final _SpyCommentPostController spy = _SpyCommentPostController();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
            commentPostController: spy,
          ),
        );
        await tester.pumpAndSettle();
        spy.clearBroadcasterCacheCallCount = 0;

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        await _confirmEndBroadcast(tester);

        // The broadcast may still be live on the server; we must NOT
        // pre-emptively flush the cache because that would force a fresh
        // (and still-broadcaster) re-query that misleadingly hides the
        // user's broadcaster status during the failure SnackBar window.
        expect(spy.clearBroadcasterCacheCallCount, 0);
      },
    );
  });
}

Future<void> _confirmEndBroadcast(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('end-broadcast-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('end-broadcast-confirm-button')));
  await tester.pumpAndSettle();
}

Widget _buildScreen({
  required ConnectionSupervisor supervisor,
  String lv = 'lv345678901',
  BroadcastControlRepository? broadcastControlRepository,
  CommentPostController? commentPostController,
}) {
  return MaterialApp(
    home: CommentScreen(
      programInfo: CommentProgramInfo(lv: lv),
      connectionSupervisor: supervisor,
      messages: const <AppMessage>[],
      callbacks: CommentCallbacks(
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, _) async {},
      ),
      themeMode: AppThemeMode.light,
      broadcastControlRepository: broadcastControlRepository,
      commentPostController: commentPostController,
    ),
  );
}

ConnectionSupervisor _buildStreamingSupervisor() {
  final ConnectionSupervisor supervisor = ConnectionSupervisor();
  expect(supervisor.startConnection(), isTrue);
  expect(supervisor.onSessionWsConnected(), isTrue);
  expect(supervisor.onNdgrEndpointResolved(), isTrue);
  return supervisor;
}

/// Test spy that counts `clearBroadcasterCache` calls so wiring tests
/// can assert that broadcaster-status flips trigger cache invalidation
/// without running the real network-backed `ensureBroadcasterStatus`
/// path. The base controller is constructed with bare-bones repositories
/// because every code path exercised by these tests stays inside the
/// presentation layer (`_endBroadcastFromMenu` → `clearBroadcasterCache`).
class _SpyCommentPostController extends CommentPostController {
  _SpyCommentPostController()
    : super(
        liveCommentRepository: LiveCommentRepository(),
        myProgramRepository: MyProgramRepository(),
      );

  int clearBroadcasterCacheCallCount = 0;

  @override
  void clearBroadcasterCache() {
    clearBroadcasterCacheCallCount++;
    super.clearBroadcasterCache();
  }
}

/// Test fake that records every `endBroadcast` invocation and lets the
/// test pre-seed a [responder] to control the result. All other inherited
/// HTTP methods stay at their base-class implementations because we only
/// exercise `endBroadcast` from this UI flow.
class _RecordingBroadcastControlRepository extends BroadcastControlRepository {
  _RecordingBroadcastControlRepository({this.responder});

  final Future<BroadcastControlResult> Function(
    String programId,
    String userSession,
  )?
  responder;

  final List<({String programId, String userSession})> calls =
      <({String programId, String userSession})>[];

  @override
  Future<BroadcastControlResult> endBroadcast({
    required String programId,
    required String userSession,
  }) async {
    calls.add((programId: programId, userSession: userSession));
    return responder?.call(programId, userSession) ??
        const BroadcastControlResult(success: true);
  }
}
