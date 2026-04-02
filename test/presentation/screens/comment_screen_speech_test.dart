import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/user_name_resolution.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';

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
      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
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

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        AppMessage(
          id: 'op-1',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
          content: '運営メッセージ',
          type: AppMessageType.operator,
        ),
      );
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

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        AppMessage(
          id: 'msg-2',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
          userId: 'blocked-user',
          content: 'ブロックされたユーザー',
          type: AppMessageType.chat,
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, isEmpty);
    });

    testWidgets('dynamically added NG user stops their TTS', (
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

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );

      // First message from the user is submitted.
      host.addMessage(
        AppMessage(
          id: 'msg-2',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
          userId: 'user-a',
          content: '普通のコメント',
          type: AppMessageType.chat,
        ),
      );
      await tester.pumpAndSettle();
      expect(fakePlatform.submittedComments, hasLength(1));

      // Now add user-a to NG list.
      host.updateNgUserIds(const <String>{'user-a'});
      await tester.pumpAndSettle();

      // Subsequent message from user-a should be skipped.
      host.addMessage(
        AppMessage(
          id: 'msg-3',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 2)),
          userId: 'user-a',
          content: 'ブロック後のコメント',
          type: AppMessageType.chat,
        ),
      );
      await tester.pumpAndSettle();
      expect(fakePlatform.submittedComments, hasLength(1));
    });

    testWidgets('removing user from NG list allows their TTS again', (
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
          ngUserIds: const <String>{'user-b'},
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );

      // Message from NG user is skipped.
      host.addMessage(
        AppMessage(
          id: 'msg-2',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
          userId: 'user-b',
          content: 'NGユーザーのコメント',
          type: AppMessageType.chat,
        ),
      );
      await tester.pumpAndSettle();
      expect(fakePlatform.submittedComments, isEmpty);

      // Remove user-b from NG list.
      host.updateNgUserIds(const <String>{});
      await tester.pumpAndSettle();

      // New message from user-b should now be submitted.
      host.addMessage(
        AppMessage(
          id: 'msg-3',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 2)),
          userId: 'user-b',
          content: 'NG解除後のコメント',
          type: AppMessageType.chat,
        ),
      );
      await tester.pumpAndSettle();
      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'NG解除後のコメント');
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

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(_chatMessage(id: 'msg-2', content: '☆秘密のコメント'));
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

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(_chatMessage(id: 'msg-2', content: '☆普通に読み上げ'));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
    });

    testWidgets('NG word messages are not submitted for speech', (
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
          ngWords: const <String>['spam', 'bad'],
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(id: 'msg-2', content: 'this is spam content'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, isEmpty);
    });

    testWidgets('NG word matching is case-insensitive', (
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
          ngWords: const <String>['spam'],
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(_chatMessage(id: 'msg-2', content: 'SPAM MESSAGE'));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, isEmpty);
    });

    testWidgets('messages without NG words are submitted normally', (
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
          ngWords: const <String>['spam', 'bad'],
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(_chatMessage(id: 'msg-2', content: 'hello world'));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'hello world');
    });

    testWidgets('readUserName ON appends nickname with さん to TTS text', (
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
          readUserName: true,
          userNicknameMap: const <String, String>{'user-1': 'テスト太郎'},
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(id: 'msg-2', content: 'こんにちは', userId: 'user-1'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'こんにちは、テスト太郎さん');
    });

    testWidgets('readUserName ON does not duplicate さん suffix', (
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
          readUserName: true,
          userNicknameMap: const <String, String>{'user-1': 'テストさん'},
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(id: 'msg-2', content: 'こんにちは', userId: 'user-1'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'こんにちは、テストさん');
    });

    testWidgets('readUserName ON does not append さん to names ending in ちゃん', (
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
          readUserName: true,
          userNicknameMap: const <String, String>{'user-1': 'テストちゃん'},
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(id: 'msg-2', content: 'こんにちは', userId: 'user-1'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'こんにちは、テストちゃん');
    });

    testWidgets('readUserName ON uses message.userName for numeric IDs', (
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
          readUserName: true,
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(
          id: 'msg-2',
          content: 'こんにちは',
          userId: '12345',
          userName: 'テスト太郎',
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'こんにちは、テスト太郎さん');
    });

    testWidgets('readUserName ON uses message.userName for non-numeric IDs', (
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
          readUserName: true,
          resolveUserName: (String _) => 'リゾルブ名',
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(
          id: 'msg-2',
          content: 'こんにちは',
          userId: 'a123',
          userName: '匿名',
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'こんにちは、匿名さん');
    });

    testWidgets('readUserName ON falls back to content only when no name', (
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
          readUserName: true,
          // No nickname mapping for 'user-1'.
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(id: 'msg-2', content: 'こんにちは', userId: 'user-1'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'こんにちは');
    });

    testWidgets(
      'readUserName ON reads resolved name when fallback resolution succeeds',
      (WidgetTester tester) async {
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            readUserName: true,
            resolveUserName: (String userId) {
              return 'should-not-use';
            },
          ),
        );
        await tester.pumpAndSettle();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(
          _chatMessage(id: 'msg-2', content: 'こんにちは', userId: '12345'),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.submittedComments, hasLength(1));
        expect(
          fakePlatform.submittedComments.first.text,
          'こんにちは、should-not-useさん',
        );
      },
    );

    testWidgets(
      'readUserName ON resolves name even when showUserName is false',
      (WidgetTester tester) async {
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            showUserName: false,
            readUserName: true,
            resolveUserName: (String userId) {
              if (userId == '12345') {
                return '解決名';
              }
              return null;
            },
          ),
        );
        await tester.pumpAndSettle();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(
          _chatMessage(id: 'msg-2', content: 'こんにちは', userId: '12345'),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.submittedComments, hasLength(1));
        expect(fakePlatform.submittedComments.first.text, 'こんにちは、解決名さん');
      },
    );

    testWidgets(
      'requests user name resolution for new comments when showUserName is false',
      (WidgetTester tester) async {
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初', userId: '11111'),
        ];
        final List<String> requestedUserIds = <String>[];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            showUserName: false,
            readUserName: true,
            requestUserNameResolve: requestedUserIds.add,
          ),
        );
        await tester.pumpAndSettle();

        // Initial messages are requested in initState.
        expect(requestedUserIds, contains('11111'));

        requestedUserIds.clear();
        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(
          _chatMessage(id: 'msg-2', content: 'こんにちは', userId: '24680'),
        );
        await tester.pumpAndSettle();

        expect(requestedUserIds, contains('24680'));
      },
    );

    testWidgets('readUserName OFF sends content only (default)', (
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
          readUserName: false,
          userNicknameMap: const <String, String>{'user-1': 'テスト太郎'},
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        _chatMessage(id: 'msg-2', content: 'こんにちは', userId: 'user-1'),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'こんにちは');
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
      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
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

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.updateSpeechSettings(
        const SpeechSettings(enabled: true, speakerId: 3),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.lastUpdatedSettings?.speakerId, 3);
    });

    testWidgets('messages with timestamp before speech init are not read', (
      WidgetTester tester,
    ) async {
      // Start with an existing message whose timestamp is in the past.
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'old-1',
          timestamp: DateTime(2020, 1, 1),
          userId: 'user-1',
          content: '過去のコメント',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          messages: messages,
        ),
      );
      await tester.pumpAndSettle();

      // Add another message with a past timestamp (simulating a backlog
      // message that arrives after speech initialization).
      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        AppMessage(
          id: 'old-2',
          timestamp: DateTime(2020, 1, 2),
          userId: 'user-1',
          content: '過去のバックログ',
          type: AppMessageType.chat,
        ),
      );
      await tester.pumpAndSettle();

      // Past-timestamp messages must be skipped.
      expect(fakePlatform.submittedComments, isEmpty);

      // A message with a future timestamp should be submitted.
      host.addMessage(_chatMessage(id: 'new-1', content: '新しいコメント'));
      await tester.pumpAndSettle();
      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, '新しいコメント');
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

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(_chatMessage(id: 'msg-2', content: 'エラーテスト'));
      await tester.pumpAndSettle();

      // Should not throw — error is caught internally.
      expect(fakePlatform.submittedComments, hasLength(1));
    });

    testWidgets('speech is stopped when broadcast ends', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        MaterialApp(
          home: CommentScreen(
            lv: 'lv123456789',
            connectionSupervisor: supervisor,
            messages: const <AppMessage>[],
            onStopAllConnections: () async {},
            onReconnectSameLv: () async {},
            onDifferentLvConnected: (_, __) async {},
            themeMode: AppThemeMode.light,
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.startCalled, isTrue);
      fakePlatform.stopCalled = false;

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      expect(fakePlatform.stopCalled, isTrue);
    });

    testWidgets(
      'speech startup aborts if the broadcast ends while start is pending',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final Completer<void> startCompleter = Completer<void>();
        fakePlatform.startCompleter = startCompleter;

        await tester.pumpWidget(
          MaterialApp(
            home: CommentScreen(
              lv: 'lv123456789',
              connectionSupervisor: supervisor,
              messages: const <AppMessage>[],
              onStopAllConnections: () async {},
              onReconnectSameLv: () async {},
              onDifferentLvConnected: (_, __) async {},
              themeMode: AppThemeMode.light,
              speechPlatform: fakePlatform,
              speechSettings: const SpeechSettings(enabled: true),
            ),
          ),
        );
        await tester.pump();

        expect(fakePlatform.startCalled, isTrue);
        expect(fakePlatform.stopCalled, isFalse);

        expect(supervisor.endBroadcast(), isTrue);
        await tester.pump();
        expect(fakePlatform.stopCalled, isFalse);

        startCompleter.complete();
        await tester.pumpAndSettle();

        expect(fakePlatform.stopCalled, isTrue);
      },
    );

    testWidgets('broadcast end does not crash when speech is disabled', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        MaterialApp(
          home: CommentScreen(
            lv: 'lv123456789',
            connectionSupervisor: supervisor,
            messages: const <AppMessage>[],
            onStopAllConnections: () async {},
            onReconnectSameLv: () async {},
            onDifferentLvConnected: (_, __) async {},
            themeMode: AppThemeMode.light,
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.startCalled, isFalse);

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      // stop is not called because speech was never started.
      expect(fakePlatform.stopCalled, isFalse);
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
    this.ngWords = const <String>[],
    this.starPrefixHidingEnabled = false,
    this.showUserName = true,
    this.readUserName = false,
    this.userNicknameMap = const <String, String>{},
    this.resolveUserName,
    this.requestUserNameResolve,
  });

  final List<AppMessage> initialMessages;
  final CommentSpeechPlatform? speechPlatform;
  final SpeechSettings speechSettings;
  final Set<String> ngUserIds;
  final List<String> ngWords;
  final bool starPrefixHidingEnabled;
  final bool showUserName;
  final bool readUserName;
  final Map<String, String> userNicknameMap;
  final String? Function(String userId)? resolveUserName;
  final void Function(String userId)? requestUserNameResolve;

  @override
  State<_SpeechTestHost> createState() => _SpeechTestHostState();
}

class _SpeechTestHostState extends State<_SpeechTestHost> {
  late List<AppMessage> _messages;
  late SpeechSettings _speechSettings;
  late Set<String> _ngUserIds;

  @override
  void initState() {
    super.initState();
    _messages = List<AppMessage>.from(widget.initialMessages);
    _speechSettings = widget.speechSettings;
    _ngUserIds = widget.ngUserIds;
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

  void updateNgUserIds(Set<String> ngUserIds) {
    setState(() {
      _ngUserIds = ngUserIds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool hasUserNameResolutionCallbacks =
        widget.resolveUserName != null || widget.requestUserNameResolve != null;
    final UserNameResolution? userNameResolution =
        hasUserNameResolutionCallbacks
        ? UserNameResolution(
            resolve: widget.resolveUserName ?? (_) => null,
            requestResolve: widget.requestUserNameResolve ?? (_) {},
            listenable: _NoopListenable.instance,
          )
        : null;

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
      ngUserIds: _ngUserIds,
      ngWords: widget.ngWords,
      starPrefixHidingEnabled: widget.starPrefixHidingEnabled,
      showUserName: widget.showUserName,
      readUserName: widget.readUserName,
      userNicknameMap: widget.userNicknameMap,
      userNameResolution: userNameResolution,
    );
  }
}

Widget _buildScreen({
  FakeCommentSpeechPlatform? speechPlatform,
  SpeechSettings speechSettings = const SpeechSettings(enabled: false),
  List<AppMessage> messages = const <AppMessage>[],
  Set<String> ngUserIds = const <String>{},
  List<String> ngWords = const <String>[],
  bool starPrefixHidingEnabled = false,
  bool showUserName = true,
  bool readUserName = false,
  Map<String, String> userNicknameMap = const <String, String>{},
  String? Function(String userId)? resolveUserName,
  void Function(String userId)? requestUserNameResolve,
}) {
  return MaterialApp(
    home: _SpeechTestHost(
      initialMessages: messages,
      speechPlatform: speechPlatform,
      speechSettings: speechSettings,
      ngUserIds: ngUserIds,
      ngWords: ngWords,
      starPrefixHidingEnabled: starPrefixHidingEnabled,
      showUserName: showUserName,
      readUserName: readUserName,
      userNicknameMap: userNicknameMap,
      resolveUserName: resolveUserName,
      requestUserNameResolve: requestUserNameResolve,
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

class _NoopListenable implements Listenable {
  const _NoopListenable._();

  static const _NoopListenable instance = _NoopListenable._();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

AppMessage _chatMessage({
  required String id,
  required String content,
  String? userId,
  String? userName,
}) {
  return AppMessage(
    id: id,
    timestamp: DateTime.now().add(const Duration(hours: 1)),
    userId: userId ?? 'user-1',
    userName: userName,
    content: content,
    type: AppMessageType.chat,
  );
}
