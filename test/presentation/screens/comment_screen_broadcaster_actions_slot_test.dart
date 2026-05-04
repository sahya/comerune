import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/extension/extension_registry.dart';
import 'package:comerune/extension/extension_scope.dart';
import 'package:comerune/extension/slot_ids.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

const Key _kSlotEntryKey = Key('test-extension-broadcaster-action');

class _NoopBroadcastControlRepository extends BroadcastControlRepository {
  @override
  Future<BroadcastControlResult> endBroadcast({
    required String programId,
    required String userSession,
  }) async {
    return const BroadcastControlResult(success: true);
  }
}

PopupMenuItem<Object> _buildExtensionEntry() {
  return PopupMenuItem<Object>(
    key: _kSlotEntryKey,
    value: const Object(),
    child: const _ExtensionMenuRow(),
  );
}

class _ExtensionMenuRow extends StatelessWidget {
  const _ExtensionMenuRow();

  @override
  Widget build(BuildContext context) {
    // mainAxisSize: min keeps the row within the PopupMenu's allotted
    // width so the test does not produce a layout overflow on narrow
    // surfaces.
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.timer_outlined),
        SizedBox(width: 12),
        Text('extend'),
      ],
    );
  }
}

void main() {
  group('CommentScreen — broadcasterScreenActions slot', () {
    testWidgets('extension entry is hidden when no extension is registered '
        '(menu unchanged from baseline)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final ExtensionRegistry registry = ExtensionRegistry();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          registry: registry,
          broadcastControlRepository: _NoopBroadcastControlRepository(),
        ),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      // Host's broadcaster entry is present.
      expect(find.byKey(const Key('end-broadcast-button')), findsOneWidget);
      // No extension entry is rendered.
      expect(find.byKey(_kSlotEntryKey), findsNothing);
    });

    testWidgets(
      'extension entry is hidden for non-broadcaster even when registered',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final ExtensionRegistry registry = ExtensionRegistry();
        registry.registerSlotWidgets(SlotIds.broadcasterScreenActions, <Widget>[
          _buildExtensionEntry(),
        ]);

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, registry: registry),
        );
        await tester.pumpAndSettle();

        // Default state: not broadcaster. Extension widgets must stay
        // hidden per the SlotIds.broadcasterScreenActions contract.
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();

        expect(find.byKey(_kSlotEntryKey), findsNothing);
      },
    );

    testWidgets('extension entry appears in broadcaster mode after the host '
        'end-broadcast entry (hostFirst order)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final ExtensionRegistry registry = ExtensionRegistry();
      registry.registerSlotWidgets(SlotIds.broadcasterScreenActions, <Widget>[
        _buildExtensionEntry(),
      ]);

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          registry: registry,
          broadcastControlRepository: _NoopBroadcastControlRepository(),
        ),
      );
      await tester.pumpAndSettle();

      (tester.state<State<CommentScreen>>(find.byType(CommentScreen))
              as CommentScreenTestAccess)
          .setBroadcasterForTesting(isBroadcaster: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      // Both the host's destructive action and the extension entry
      // are now visible.
      final Finder hostEnd = find.byKey(const Key('end-broadcast-button'));
      final Finder extension = find.byKey(_kSlotEntryKey);
      expect(hostEnd, findsOneWidget);
      expect(extension, findsOneWidget);

      // hostFirst order: the host entry's vertical position must be
      // above the extension entry on the screen.
      final Offset hostCentre = tester.getCenter(hostEnd);
      final Offset extensionCentre = tester.getCenter(extension);
      expect(
        hostCentre.dy < extensionCentre.dy,
        isTrue,
        reason:
            'Host end-broadcast entry should appear before the extension '
            'entry in hostFirst order.',
      );
    });
  });
}

Widget _buildScreen({
  required ConnectionSupervisor supervisor,
  required ExtensionRegistry registry,
  String lv = 'lv345678901',
  BroadcastControlRepository? broadcastControlRepository,
}) {
  return MaterialApp(
    home: ExtensionScope(
      registry: registry,
      child: CommentScreen(
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
