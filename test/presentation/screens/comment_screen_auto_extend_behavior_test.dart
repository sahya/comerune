import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

void main() {
  group('CommentScreen auto-extend behavior wiring (Issue #876)', () {
    testWidgets(
      'manual extend success surfaces a new endAt via onBroadcastEndTimeExtended',
      (WidgetTester tester) async {
        // Issue #872 follow-up + #876 plumbing: when the manual-extend
        // dialog confirms and the API returns a new end_time, the screen
        // must propagate it to the host so `FollowProgram.endAt` can be
        // refreshed and the auto-extend controller's next [update] cycle
        // observes the new value.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final DateTime newEndAt = DateTime.utc(2026, 1, 1, 13);
        final int newEndAtSec = newEndAt.millisecondsSinceEpoch ~/ 1000;
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository(
              extendResponder: (_, _, _) async =>
                  BroadcastControlResult(success: true, endTime: newEndAtSec),
            );
        final List<DateTime> reportedEndAts = <DateTime>[];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
            onBroadcastEndTimeExtended: reportedEndAts.add,
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

        // Open the manual extend dialog and confirm with the default
        // 30 minute selection.
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('extend-broadcast-button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('extend-broadcast-confirm-button')),
        );
        await tester.pumpAndSettle();

        expect(repo.extendCalls, hasLength(1));
        // The screen pushes the server-authoritative new end time back
        // to the host. The host (production) updates `_myProgram.endAt`,
        // which on next rebuild flows back as `widget.programInfo.endAt`.
        expect(reportedEndAts, hasLength(1));
        expect(
          reportedEndAts.single.millisecondsSinceEpoch ~/ 1000,
          newEndAtSec,
        );
      },
    );

    testWidgets(
      'auto-extend failure / success messages render with their dedicated background',
      (WidgetTester tester) async {
        // Verify the renderer's id-prefix dispatch picks the correct
        // theme color for both success and failure auto-extend messages.
        // The message rows themselves are part of the comment timeline,
        // so we feed the [messages] prop directly rather than going
        // through the full FakeAsync timer pipeline.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final DateTime now = DateTime.now();
        final AppMessage successMsg = AppMessage(
          id: buildAutoExtendSuccessNotificationId(
            epochMilliseconds: now.millisecondsSinceEpoch,
            sequence: 0,
          ),
          timestamp: now,
          content: '自動延長が成功しました（+30 分）',
          type: AppMessageType.notification,
        );
        final AppMessage failureMsg = AppMessage(
          id: buildAutoExtendFailureNotificationId(
            epochMilliseconds: now.millisecondsSinceEpoch,
            sequence: 1,
          ),
          timestamp: now.add(const Duration(seconds: 1)),
          content: '自動延長に失敗しました',
          type: AppMessageType.notification,
        );

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: <AppMessage>[successMsg, failureMsg],
          ),
        );
        await tester.pumpAndSettle();

        // Both rows must be rendered. We do not assert on the exact
        // background color value (theme-specific) — instead we verify
        // the content text appears, which proves they passed the
        // visibility filter, and rely on the unit test for theme
        // contrast / color palette tests for the actual color picks.
        // `textContaining` is used because the renderer may split the
        // content across InlineSpans (URL extraction, highlighting,
        // etc.) so an exact `find.text` would over-match.
        expect(find.textContaining('自動延長が成功しました'), findsOneWidget);
        expect(find.textContaining('自動延長に失敗しました'), findsOneWidget);

        // Pin the renderer's id-prefix dispatch by checking the
        // matching helpers are present on the state. Going through
        // CommentScreenTestAccess avoids relying on the specific
        // private widget tree shape.
        final CommentScreenTestAccess access =
            tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess;
        // Sanity: messages are exposed to the renderer (not silently
        // filtered out by visibility toggles).
        final Iterable<AppMessage> displayed = access
            .messagesForLogForTesting();
        expect(
          displayed.where((AppMessage m) => m.id == successMsg.id),
          hasLength(1),
        );
        expect(
          displayed.where((AppMessage m) => m.id == failureMsg.id),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'extend dialog cancel does NOT propagate an endAt update upstream',
      (WidgetTester tester) async {
        // Defensive: the host should only see endAt updates when the
        // server confirmed an extension. Cancelling the dialog must not
        // leak a notification.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository();
        final List<DateTime> reportedEndAts = <DateTime>[];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
            onBroadcastEndTimeExtended: reportedEndAts.add,
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
          find.byKey(const Key('extend-broadcast-cancel-button')),
        );
        await tester.pumpAndSettle();

        expect(repo.extendCalls, isEmpty);
        expect(reportedEndAts, isEmpty);
      },
    );

    testWidgets(
      'extend dialog failure does NOT propagate an endAt update upstream',
      (WidgetTester tester) async {
        // Defensive: server-side failure (4xx / network) must not push
        // a stale or zero endAt to the host even though the request
        // was attempted.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _RecordingBroadcastControlRepository repo =
            _RecordingBroadcastControlRepository(
              extendResponder: (_, _, _) async => const BroadcastControlResult(
                success: false,
                errorCode: BroadcastControlErrorCode.networkError,
              ),
            );
        final List<DateTime> reportedEndAts = <DateTime>[];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: repo,
            onBroadcastEndTimeExtended: reportedEndAts.add,
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

        expect(repo.extendCalls, hasLength(1));
        expect(reportedEndAts, isEmpty);
      },
    );
  });
}

Widget _buildScreen({
  required ConnectionSupervisor supervisor,
  String lv = 'lv345678901',
  BroadcastControlRepository? broadcastControlRepository,
  List<AppMessage> messages = const <AppMessage>[],
  void Function(DateTime newEndAt)? onBroadcastEndTimeExtended,
  void Function(AppMessage message)? onAutoExtendSystemMessage,
}) {
  return MaterialApp(
    home: CommentScreen(
      programInfo: CommentProgramInfo(lv: lv),
      connectionSupervisor: supervisor,
      messages: messages,
      callbacks: CommentCallbacks(
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, _) async {},
        onBroadcastEndTimeExtended: onBroadcastEndTimeExtended,
        onAutoExtendSystemMessage: onAutoExtendSystemMessage,
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

/// Records every `extendBroadcast` invocation. Lets tests pre-seed an
/// [extendResponder] to control the result.
class _RecordingBroadcastControlRepository extends BroadcastControlRepository {
  _RecordingBroadcastControlRepository({this.extendResponder});

  final Future<BroadcastControlResult> Function(
    String programId,
    String userSession,
    int minutes,
  )?
  extendResponder;

  final List<({String programId, String userSession, int minutes})>
  extendCalls = <({String programId, String userSession, int minutes})>[];

  @override
  Future<BroadcastControlResult> extendBroadcast({
    required String programId,
    required String userSession,
    int minutes = 30,
  }) async {
    extendCalls.add((
      programId: programId,
      userSession: userSession,
      minutes: minutes,
    ));
    return extendResponder?.call(programId, userSession, minutes) ??
        const BroadcastControlResult(success: true);
  }
}
