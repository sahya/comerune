import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

void main() {
  group('CommentScreen AppBar overflow "放送を延長" entry', () {
    testWidgets('is hidden by default (non-broadcaster, no repository)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(_buildScreen(supervisor: supervisor));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('extend-broadcast-button')), findsNothing);
      // Sanity: other items still render so the menu itself is healthy.
      expect(find.byKey(const Key('comment-search-button')), findsOneWidget);
    });

    testWidgets('is hidden for broadcaster when no repository is wired', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(_buildScreen(supervisor: supervisor));
      await tester.pumpAndSettle();

      final CommentScreenTestAccess access =
          tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess;
      access.setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('extend-broadcast-button')), findsNothing);
    });

    testWidgets(
      'is shown in default text color (not destructive) for broadcaster + repository',
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

        final Finder entry = find.byKey(const Key('extend-broadcast-button'));
        expect(entry, findsOneWidget);

        // Label color must be the default (null/unspecified) so the row
        // does not pick up the destructive error color reserved for
        // "配信を終了". Confirms the OverflowMenuRow `labelColor`
        // contract for non-destructive entries.
        final Text labelText = tester.widget(
          find.descendant(of: entry, matching: find.text('放送を延長')),
        );
        expect(labelText.style?.color, isNull);
      },
    );

    testWidgets(
      'menu lays the extend entry above end-broadcast and search/save/settings',
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

        final double extendY = tester
            .getCenter(find.byKey(const Key('extend-broadcast-button')))
            .dy;
        final double endY = tester
            .getCenter(find.byKey(const Key('end-broadcast-button')))
            .dy;
        final double searchY = tester
            .getCenter(find.byKey(const Key('comment-search-button')))
            .dy;
        expect(
          extendY < endY,
          isTrue,
          reason:
              'extend-broadcast must render above end-broadcast so the '
              'destructive end action stays distinct',
        );
        expect(
          endY < searchY,
          isTrue,
          reason:
              'end-broadcast must remain above the search row to '
              'preserve the existing menu order',
        );
      },
    );

    testWidgets('cancelling the dialog does not call repository', (
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
          .setBroadcasterForTesting(
            isBroadcaster: true,
            userSession: 'session-abc',
          );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('extend-broadcast-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('extend-broadcast-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('extend-broadcast-cancel-button')));
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
      expect(find.byKey(const Key('extend-broadcast-dialog')), findsNothing);
      expect(
        find.byKey(const Key('extend-broadcast-success-snackbar')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('extend-broadcast-failure-snackbar')),
        findsNothing,
      );
    });

    testWidgets(
      'confirm calls repository.extendBroadcast with current lv + session + default 30 minutes',
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
              userSession: 'session-xyz',
            );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('extend-broadcast-button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('extend-broadcast-confirm-button')),
        );
        await tester.pumpAndSettle();

        expect(repo.calls, hasLength(1));
        expect(repo.calls.single.programId, 'lv12345');
        expect(repo.calls.single.userSession, 'session-xyz');
        expect(repo.calls.single.minutes, 30);
      },
    );

    testWidgets('success surfaces the success SnackBar with selected minutes', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository(
            responder: (_, _, _) async =>
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

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('extend-broadcast-button')));
      await tester.pumpAndSettle();

      // Pick 60 minutes via the dropdown overlay.
      await tester.tap(
        find.byKey(const Key('extend-broadcast-minutes-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('60 分').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('extend-broadcast-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('extend-broadcast-success-snackbar')),
        findsOneWidget,
      );
      expect(find.text('放送を 60 分延長しました'), findsOneWidget);
    });

    testWidgets('failure surfaces the generic failure SnackBar', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository(
            responder: (_, _, _) async => const BroadcastControlResult(
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

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('extend-broadcast-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('extend-broadcast-confirm-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('extend-broadcast-failure-snackbar')),
        findsOneWidget,
      );
      expect(find.text('放送を延長できませんでした'), findsOneWidget);
    });

    testWidgets('empty session surfaces the session-required SnackBar', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _RecordingBroadcastControlRepository repo =
          _RecordingBroadcastControlRepository();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, broadcastControlRepository: repo),
      );
      await tester.pumpAndSettle();

      // Broadcaster mode but session explicitly empty so the screen-level
      // session-required guard fires before the dialog opens.
      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true, userSession: '');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('extend-broadcast-button')));
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
      expect(find.byKey(const Key('extend-broadcast-dialog')), findsNothing);
      expect(
        find.byKey(const Key('extend-broadcast-session-required-snackbar')),
        findsOneWidget,
      );
    });

    testWidgets(
      'in-flight extension keeps the dialog up and disables both buttons',
      (WidgetTester tester) async {
        // The screen-level `_isExtendingBroadcast` guard exists as
        // defense-in-depth, but the visible re-entrancy contract during
        // in-flight is delivered by the dialog itself: while the API is
        // pending the dialog stays modal, the dropdown is disabled, and
        // both buttons are disabled. This test pins that wire-up at the
        // screen integration boundary so future refactors cannot drop
        // the in-flight modal property silently.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final Completer<BroadcastControlResult> pending =
            Completer<BroadcastControlResult>();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository(
              responder: (_, _, _) => pending.future,
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

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('extend-broadcast-button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('extend-broadcast-confirm-button')),
        );
        // Bounded pumps because the spinner is animating indefinitely.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Dialog must still be on top of the menu (modal).
        expect(
          find.byKey(const Key('extend-broadcast-dialog')),
          findsOneWidget,
        );
        // Both buttons disabled while pending.
        final FilledButton confirmButton = tester.widget(
          find.byKey(const Key('extend-broadcast-confirm-button')),
        );
        final TextButton cancelButton = tester.widget(
          find.byKey(const Key('extend-broadcast-cancel-button')),
        );
        expect(confirmButton.onPressed, isNull);
        expect(cancelButton.onPressed, isNull);
        // Repository was hit exactly once even with the spinner still up.
        expect(repo.calls, hasLength(1));

        // Drain the pending future so the test exits cleanly.
        pending.complete(const BroadcastControlResult(success: true));
        await tester.pumpAndSettle();
      },
    );
  });
}

Widget _buildScreen({
  required ConnectionSupervisor supervisor,
  String lv = 'lv345678901',
  BroadcastControlRepository? broadcastControlRepository,
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

/// Records every `extendBroadcast` call so wiring tests can assert
/// program / session / minutes propagation. Other inherited HTTP methods
/// stay at their base-class implementations because we only exercise
/// `extendBroadcast` from the menu flow.
class _RecordingBroadcastControlRepository extends BroadcastControlRepository {
  _RecordingBroadcastControlRepository({this.responder});

  final Future<BroadcastControlResult> Function(
    String programId,
    String userSession,
    int minutes,
  )?
  responder;

  final List<({String programId, String userSession, int minutes})> calls =
      <({String programId, String userSession, int minutes})>[];

  @override
  Future<BroadcastControlResult> extendBroadcast({
    required String programId,
    required String userSession,
    int minutes = 30,
  }) async {
    calls.add((
      programId: programId,
      userSession: userSession,
      minutes: minutes,
    ));
    return responder?.call(programId, userSession, minutes) ??
        const BroadcastControlResult(success: true);
  }
}
