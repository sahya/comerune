import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';

void main() {
  group('CommentScreen speech integration', () {
    late FakeCommentSpeechPlatform fakePlatform;

    setUp(() {
      fakePlatform = FakeCommentSpeechPlatform();
      // Engine already ready so setup dialog is not shown.
      fakePlatform.statusToReturn = const SpeechRuntimeStatus(
        enabled: true,
        engineState: 'READY',
        playerState: 'IDLE',
        queueSize: 0,
        currentSpeakerId: 0,
      );
    });

    tearDown(() {
      fakePlatform.dispose();
    });

    testWidgets('speech status icon is shown when speech is enabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('speech-status-icon')), findsOneWidget);
    });

    testWidgets('speech status icon is hidden when speech is disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('speech-status-icon')), findsNothing);
    });

    testWidgets('engine is initialized and started when speech is enabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.startCalled, isTrue);
      expect(fakePlatform.lastUpdatedSettings?.enabled, isTrue);
    });

    testWidgets('new chat messages are submitted for speech', (
      WidgetTester tester,
    ) async {
      final List<AppMessage> messages = <AppMessage>[
        _chatMessage(id: 'msg-1', content: 'こんにちは'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          messages: messages,
        ),
      );
      await tester.pumpAndSettle();

      // Add a new message.
      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.addMessage(_chatMessage(id: 'msg-2', content: '新しいコメント'));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, '新しいコメント');
    });

    testWidgets('non-chat messages are not submitted for speech', (
      WidgetTester tester,
    ) async {
      final List<AppMessage> messages = <AppMessage>[
        _chatMessage(id: 'msg-1', content: '最初'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          messages: messages,
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.addMessage(AppMessage(
        id: 'op-1',
        timestamp: DateTime(2026, 3, 30, 12, 0, 1),
        content: '運営メッセージ',
        type: AppMessageType.operator,
      ));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, isEmpty);
    });

    testWidgets('NG user messages are not submitted for speech', (
      WidgetTester tester,
    ) async {
      final List<AppMessage> messages = <AppMessage>[
        _chatMessage(id: 'msg-1', content: '最初'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          messages: messages,
          ngUserIds: const <String>{'blocked-user'},
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.addMessage(AppMessage(
        id: 'msg-2',
        timestamp: DateTime(2026, 3, 30, 12, 0, 1),
        userId: 'blocked-user',
        content: 'ブロックされたユーザー',
        type: AppMessageType.chat,
      ));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, isEmpty);
    });

    testWidgets('star-prefix messages are not submitted when hiding enabled', (
      WidgetTester tester,
    ) async {
      final List<AppMessage> messages = <AppMessage>[
        _chatMessage(id: 'msg-1', content: '最初'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          messages: messages,
          starPrefixHidingEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.addMessage(
        _chatMessage(id: 'msg-2', content: '☆秘密のコメント'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, isEmpty);
    });

    testWidgets('star-prefix messages are submitted when hiding disabled', (
      WidgetTester tester,
    ) async {
      final List<AppMessage> messages = <AppMessage>[
        _chatMessage(id: 'msg-1', content: '最初'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          messages: messages,
          starPrefixHidingEnabled: false,
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.addMessage(
        _chatMessage(id: 'msg-2', content: '☆普通に読み上げ'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
    });

    testWidgets('speech is stopped when settings change to disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(fakePlatform.startCalled, isTrue);

      // Disable speech.
      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.updateSpeechSettings(const SpeechSettings(enabled: false));
      await tester.pumpAndSettle();

      expect(fakePlatform.stopCalled, isTrue);
    });

    testWidgets('settings are pushed to engine when changed while active', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true, speakerId: 0),
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.updateSpeechSettings(
        const SpeechSettings(enabled: true, speakerId: 3),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.lastUpdatedSettings?.speakerId, 3);
    });

    testWidgets('submitComment error does not crash', (
      WidgetTester tester,
    ) async {
      fakePlatform.submitCommentError = Exception('network error');

      final List<AppMessage> messages = <AppMessage>[
        _chatMessage(id: 'msg-1', content: '最初'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          messages: messages,
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host =
          tester.state(find.byType(_SpeechTestHost));
      host.addMessage(_chatMessage(id: 'msg-2', content: 'エラーテスト'));
      await tester.pumpAndSettle();

      // Should not throw — error is caught internally.
      expect(fakePlatform.submittedComments, hasLength(1));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Stateful host widget to allow updating messages and settings during tests.
class _SpeechTestHost extends StatefulWidget {
  const _SpeechTestHost({
    required this.initialMessages,
    required this.speechPlatform,
    required this.speechSettings,
    this.ngUserIds = const <String>{},
    this.starPrefixHidingEnabled = false,
  });

  final List<AppMessage> initialMessages;
  final CommentSpeechPlatform? speechPlatform;
  final SpeechSettings speechSettings;
  final Set<String> ngUserIds;
  final bool starPrefixHidingEnabled;

  @override
  State<_SpeechTestHost> createState() => _SpeechTestHostState();
}

class _SpeechTestHostState extends State<_SpeechTestHost> {
  late List<AppMessage> _messages;
  late SpeechSettings _speechSettings;

  @override
  void initState() {
    super.initState();
    _messages = List<AppMessage>.from(widget.initialMessages);
    _speechSettings = widget.speechSettings;
  }

  void addMessage(AppMessage message) {
    setState(() {
      _messages = List<AppMessage>.from(_messages)..add(message);
    });
  }

  void updateSpeechSettings(SpeechSettings settings) {
    setState(() {
      _speechSettings = settings;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CommentScreen(
      lv: 'lv123456789',
      connectionSupervisor: _buildStreamingSupervisor(),
      messages: _messages,
      onStopAllConnections: () async {},
      onReconnectSameLv: () async {},
      onDifferentLvConnected: (_, __) async {},
      themeMode: AppThemeMode.light,
      speechPlatform: widget.speechPlatform,
      speechSettings: _speechSettings,
      ngUserIds: widget.ngUserIds,
      starPrefixHidingEnabled: widget.starPrefixHidingEnabled,
    );
  }
}

Widget _buildScreen({
  FakeCommentSpeechPlatform? speechPlatform,
  SpeechSettings speechSettings = const SpeechSettings(enabled: false),
  List<AppMessage> messages = const <AppMessage>[],
  Set<String> ngUserIds = const <String>{},
  bool starPrefixHidingEnabled = false,
}) {
  return MaterialApp(
    home: _SpeechTestHost(
      initialMessages: messages,
      speechPlatform: speechPlatform,
      speechSettings: speechSettings,
      ngUserIds: ngUserIds,
      starPrefixHidingEnabled: starPrefixHidingEnabled,
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

AppMessage _chatMessage({
  required String id,
  required String content,
  String? userId,
}) {
  return AppMessage(
    id: id,
    timestamp: DateTime(2026, 3, 30, 12, 0, 0),
    userId: userId ?? 'user-1',
    content: content,
    type: AppMessageType.chat,
  );
}
