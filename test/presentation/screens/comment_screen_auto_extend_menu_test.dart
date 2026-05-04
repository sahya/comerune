import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

void main() {
  group('CommentScreen AppBar overflow "自動延長" toggle', () {
    testWidgets('is hidden by default (non-broadcaster, no repository)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(_buildScreen(supervisor: supervisor));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('auto-extend-broadcast-toggle')),
        findsNothing,
      );
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

      expect(
        find.byKey(const Key('auto-extend-broadcast-toggle')),
        findsNothing,
      );
    });

    testWidgets(
      'is shown for broadcaster + repository, with Switch reflecting the param',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: _NoOpBroadcastControlRepository(),
            autoExtendBroadcastEnabled: true,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('auto-extend-broadcast-toggle')),
          findsOneWidget,
        );
        // Switch displays the initial param value.
        final Switch switchWidget = tester.widget<Switch>(
          find.descendant(
            of: find.byKey(const Key('auto-extend-broadcast-toggle')),
            matching: find.byType(Switch),
          ),
        );
        expect(switchWidget.value, isTrue);
      },
    );

    testWidgets(
      'menu lays the auto-extend toggle between manual extend and end-broadcast',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: _NoOpBroadcastControlRepository(),
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
        final double autoExtendY = tester
            .getCenter(find.byKey(const Key('auto-extend-broadcast-toggle')))
            .dy;
        final double endY = tester
            .getCenter(find.byKey(const Key('end-broadcast-button')))
            .dy;
        expect(
          extendY < autoExtendY,
          isTrue,
          reason:
              'manual extend stays above auto-extend (action first, '
              'persistent toggle second)',
        );
        expect(
          autoExtendY < endY,
          isTrue,
          reason:
              'auto-extend stays above end-broadcast so the destructive '
              'end action remains the bottom-most broadcaster control',
        );
      },
    );

    testWidgets(
      'tapping the row invokes onAutoExtendBroadcastChanged with the toggled value',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<bool> reportedValues = <bool>[];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: _NoOpBroadcastControlRepository(),
            autoExtendBroadcastEnabled: false,
            onAutoExtendBroadcastChanged: reportedValues.add,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('auto-extend-broadcast-toggle')));
        await tester.pumpAndSettle();

        // Off → On
        expect(reportedValues, <bool>[true]);

        // Re-open the menu — Switch must reflect the new local value
        // even before the host has persisted anything (UI uses an
        // optimistic local cache; the host echoes the value back via
        // didUpdateWidget on subsequent rebuilds).
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        Switch switchWidget = tester.widget<Switch>(
          find.descendant(
            of: find.byKey(const Key('auto-extend-broadcast-toggle')),
            matching: find.byType(Switch),
          ),
        );
        expect(switchWidget.value, isTrue);

        // Tap again — On → Off
        await tester.tap(find.byKey(const Key('auto-extend-broadcast-toggle')));
        await tester.pumpAndSettle();
        expect(reportedValues, <bool>[true, false]);

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        switchWidget = tester.widget<Switch>(
          find.descendant(
            of: find.byKey(const Key('auto-extend-broadcast-toggle')),
            matching: find.byType(Switch),
          ),
        );
        expect(switchWidget.value, isFalse);
      },
    );

    testWidgets(
      'parent re-passing a different autoExtendBroadcastEnabled re-seeds the local cache',
      (WidgetTester tester) async {
        // Issue #875: Settings Import / restore-defaults path. The
        // parent ValueNotifier flips and the child must reflect the new
        // value rather than keeping the user’s last manual toggle.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: _NoOpBroadcastControlRepository(),
            autoExtendBroadcastEnabled: false,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        // Parent rebuilds with the prop flipped.
        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            broadcastControlRepository: _NoOpBroadcastControlRepository(),
            autoExtendBroadcastEnabled: true,
          ),
        );
        await tester.pumpAndSettle();

        (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
                as CommentScreenTestAccess)
            .setBroadcasterForTesting(isBroadcaster: true);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();

        final Switch switchWidget = tester.widget<Switch>(
          find.descendant(
            of: find.byKey(const Key('auto-extend-broadcast-toggle')),
            matching: find.byType(Switch),
          ),
        );
        expect(switchWidget.value, isTrue);
      },
    );
  });
}

Widget _buildScreen({
  required ConnectionSupervisor supervisor,
  String lv = 'lv345678901',
  BroadcastControlRepository? broadcastControlRepository,
  bool autoExtendBroadcastEnabled = false,
  void Function(bool enabled)? onAutoExtendBroadcastChanged,
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
        onAutoExtendBroadcastChanged: onAutoExtendBroadcastChanged,
      ),
      themeMode: AppThemeMode.light,
      broadcastControlRepository: broadcastControlRepository,
      autoExtendBroadcastEnabled: autoExtendBroadcastEnabled,
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

/// Stub Repository that is wired only to satisfy `canEndBroadcast`'s
/// non-null check. None of these tests exercise the network-bound
/// methods so all overrides return without touching the base class.
class _NoOpBroadcastControlRepository extends BroadcastControlRepository {
  _NoOpBroadcastControlRepository();
}
