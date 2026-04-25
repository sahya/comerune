import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/user_name_resolution.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

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

    testWidgets(
      'gift messages are not submitted when readGiftComment is false',
      (WidgetTester tester) async {
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
            id: 'gift-1',
            timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
            content: 'ギフト本文',
            type: AppMessageType.gift,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.submittedComments, isEmpty);
      },
    );

    testWidgets(
      'gift messages speak only the body when readGiftComment is true',
      (WidgetTester tester) async {
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            readGiftComment: true,
            // readUserName ON must NOT prepend a user name to gift speech.
            readUserName: true,
          ),
        );
        await tester.pumpAndSettle();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(
          AppMessage(
            id: 'gift-1',
            timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
            userId: 'advertiser-1',
            userName: '広告主',
            content: 'ギフト本文',
            type: AppMessageType.gift,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.submittedComments, hasLength(1));
        expect(fakePlatform.submittedComments.first.text, 'ギフト本文');
      },
    );

    testWidgets(
      'nicoad messages are not submitted when readNicoadComment is false',
      (WidgetTester tester) async {
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
            id: 'nicoad-1',
            timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
            content: 'ニコニ広告本文',
            type: AppMessageType.nicoad,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.submittedComments, isEmpty);
      },
    );

    testWidgets(
      'nicoad messages speak only the body when readNicoadComment is true',
      (WidgetTester tester) async {
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            readNicoadComment: true,
          ),
        );
        await tester.pumpAndSettle();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(
          AppMessage(
            id: 'nicoad-1',
            timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
            content: 'ニコニ広告本文',
            type: AppMessageType.nicoad,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.submittedComments, hasLength(1));
        expect(fakePlatform.submittedComments.first.text, 'ニコニ広告本文');
      },
    );

    testWidgets(
      'gift speech bypasses NG word filter (body may contain NG words)',
      (WidgetTester tester) async {
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            readGiftComment: true,
            ngWords: const <String>['ng'],
          ),
        );
        await tester.pumpAndSettle();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(
          AppMessage(
            id: 'gift-1',
            timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
            content: 'NG word gift body',
            type: AppMessageType.gift,
          ),
        );
        await tester.pumpAndSettle();

        // Gift is a system-generated event and is not subject to chat NG filters.
        expect(fakePlatform.submittedComments, hasLength(1));
        expect(fakePlatform.submittedComments.first.text, 'NG word gift body');
      },
    );

    testWidgets('nicoad speech is skipped when body contains an NG word', (
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
          readNicoadComment: true,
          ngWords: const <String>['ng'],
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(
        AppMessage(
          id: 'nicoad-ng',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
          content: 'this contains NG text',
          type: AppMessageType.nicoad,
        ),
      );
      // Send a clean nicoad right after to confirm the pipeline still
      // flows for non-matching bodies (regression guard against a
      // too-aggressive filter or short-circuited iteration).
      host.addMessage(
        AppMessage(
          id: 'nicoad-clean',
          timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 2)),
          content: 'clean nicoad body',
          type: AppMessageType.nicoad,
        ),
      );
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'clean nicoad body');
    });

    testWidgets(
      'empty-body gift messages are skipped even when readGiftComment is true',
      (WidgetTester tester) async {
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            readGiftComment: true,
            readNicoadComment: true,
          ),
        );
        await tester.pumpAndSettle();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(
          AppMessage(
            id: 'gift-empty',
            timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 1)),
            content: '',
            type: AppMessageType.gift,
          ),
        );
        host.addMessage(
          AppMessage(
            id: 'nicoad-empty',
            timestamp: DateTime.now().add(const Duration(hours: 1, seconds: 2)),
            content: '',
            type: AppMessageType.nicoad,
          ),
        );
        await tester.pumpAndSettle();

        // Empty content must not be submitted — TTS engines would either
        // error or speak nothing useful.
        expect(fakePlatform.submittedComments, isEmpty);
      },
    );

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

    testWidgets('slash-prefix messages are not submitted when skip enabled', (
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
          slashPrefixSkipEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(_chatMessage(id: 'msg-2', content: '/info 読み上げ対象外'));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, isEmpty);
    });

    testWidgets('slash-prefix messages are submitted when skip disabled', (
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
          slashPrefixSkipEnabled: false,
        ),
      );
      await tester.pumpAndSettle();

      final _SpeechTestHostState host = tester.state(
        find.byType(_SpeechTestHost),
      );
      host.addMessage(_chatMessage(id: 'msg-2', content: '/info 読み上げ対象'));
      await tester.pumpAndSettle();

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, '/info 読み上げ対象');
    });

    testWidgets(
      'teach/unteach commands are never read aloud regardless of slash skip',
      (WidgetTester tester) async {
        // Guards the ordering in _submitNewCommentsForSpeech: even when
        // slash-prefix skip is disabled (meaning `/foo` would otherwise be
        // spoken), `/teach` and `/unteach` must be intercepted by the teach
        // handler and never sent to TTS. This protects against regressions
        // where the slash-prefix skip check is moved before the teach check.
        final List<AppMessage> messages = <AppMessage>[
          _chatMessage(id: 'msg-1', content: '最初'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            messages: messages,
            slashPrefixSkipEnabled: false,
          ),
        );
        await tester.pumpAndSettle();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.addMessage(_chatMessage(id: 'msg-2', content: '/teach パターン よみがな'));
        host.addMessage(_chatMessage(id: 'msg-3', content: '/unteach パターン'));
        await tester.pumpAndSettle();

        expect(fakePlatform.submittedComments, isEmpty);
      },
    );

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
            programInfo: const CommentProgramInfo(lv: 'lv123456789'),
            connectionSupervisor: supervisor,
            messages: const <AppMessage>[],
            callbacks: CommentCallbacks(
              onStopAllConnections: () async {},
              onReconnectSameLv: () async {},
              onDifferentLvConnected: (_, _) async {},
            ),
            themeMode: AppThemeMode.light,
            speechConfig: CommentSpeechConfig(
              speechPlatform: fakePlatform,
              speechSettings: const SpeechSettings(enabled: true),
            ),
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
              programInfo: const CommentProgramInfo(lv: 'lv123456789'),
              connectionSupervisor: supervisor,
              messages: const <AppMessage>[],
              callbacks: CommentCallbacks(
                onStopAllConnections: () async {},
                onReconnectSameLv: () async {},
                onDifferentLvConnected: (_, _) async {},
              ),
              themeMode: AppThemeMode.light,
              speechConfig: CommentSpeechConfig(
                speechPlatform: fakePlatform,
                speechSettings: const SpeechSettings(enabled: true),
              ),
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
            programInfo: const CommentProgramInfo(lv: 'lv123456789'),
            connectionSupervisor: supervisor,
            messages: const <AppMessage>[],
            callbacks: CommentCallbacks(
              onStopAllConnections: () async {},
              onReconnectSameLv: () async {},
              onDifferentLvConnected: (_, _) async {},
            ),
            themeMode: AppThemeMode.light,
            speechConfig: CommentSpeechConfig(
              speechPlatform: fakePlatform,
              speechSettings: const SpeechSettings(enabled: false),
            ),
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

  // Regression coverage for Issue #682. Android TTS does not show the VOICEVOX
  // setup dialog, but the native AndroidTtsSpeaker still has to be brought to
  // ready=true. We call `checkAndroidTtsAvailability()` (not `initialize()`)
  // because the native "initialize" handler also drives VOICEVOX engine init,
  // which fails with `MissingAssetsException` for users who never downloaded
  // VOICEVOX dict/VVM — and that would mask a perfectly functional Android
  // TTS as an error. `checkAndroidTtsAvailability` touches only
  // `AndroidTtsSpeaker.initialize()` on the native side, which is exactly
  // what Android-TTS-only users need.
  group('CommentScreen speech integration (Android TTS)', () {
    late FakeCommentSpeechPlatform fakePlatform;

    setUp(() {
      fakePlatform = FakeCommentSpeechPlatform();
      // Engine is NOT ready yet — this is the first connection since app
      // launch and the user has never opened the TTS settings screen.
      fakePlatform.statusToReturn = const SpeechRuntimeStatus(
        enabled: true,
        engineState: 'UNINITIALIZED',
        playerState: 'UNKNOWN',
        queueSize: 0,
        currentSpeakerId: 0,
      );
    });

    tearDown(() {
      fakePlatform.dispose();
    });

    testWidgets(
      'Android TTS branch initializes the native speaker without triggering VOICEVOX engine init',
      (WidgetTester tester) async {
        fakePlatform.androidTtsAvailableToReturn = true;

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The core regression assertion: without this path the native
        // AndroidTtsSpeaker stays ready=false and drops every comment.
        expect(fakePlatform.checkAndroidTtsAvailabilityCalled, isTrue);
        // `initialize()` must NOT be called on this branch. The generic
        // initialize handler would also bootstrap VOICEVOX engine, which
        // fails with MissingAssetsException for Android-TTS-only users that
        // never downloaded any VOICEVOX assets — regressing the very bug
        // this PR is trying to fix (Issue #682 case 1).
        expect(fakePlatform.initializeCalled, isFalse);
        // After the Android TTS speaker is ready, speech must reach start()
        // so the worker loop picks up queued comments.
        expect(fakePlatform.startCalled, isTrue);
      },
    );

    testWidgets(
      'Android TTS unavailable surfaces the ERROR icon and does not start speech',
      (WidgetTester tester) async {
        // Native speaker initialization failed (e.g. Japanese voice data
        // missing). checkAndroidTtsAvailability returns false.
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.checkAndroidTtsAvailabilityCalled, isTrue);
        expect(
          fakePlatform.checkAndroidTtsAvailabilityCallCount,
          1,
          reason: 'availability must be checked exactly once per init attempt',
        );
        // start() must NOT be called when the speaker isn't ready, otherwise
        // the worker loop would run against an un-ready speaker and drop
        // every comment.
        expect(fakePlatform.startCalled, isFalse);

        // UI feedback requirement for Issue #682 acceptance criteria ("the
        // user must be able to notice the failure"): the status icon must
        // show the ERROR state, NOT the neutral hourglass ("初期化中") or
        // pause ("停止中") icons. The status icon widget evaluates ERROR
        // before the initialized/started branches precisely so this holds.
        expect(
          find.byIcon(Icons.error_outline),
          findsOneWidget,
          reason:
              'Android TTS availability failure must surface the ERROR icon '
              'so the user can notice the failure per Issue #682.',
        );
        expect(find.byIcon(Icons.hourglass_top), findsNothing);
        expect(find.byIcon(Icons.pause_circle_outline), findsNothing);

        // Accessibility regression guard: the ERROR branch renders the icon
        // inside a non-interactive `Semantics(label: '読み上げ: エラー', ...)`
        // wrapper (see `_SpeechStatusIcon.build()`). Screen reader users must
        // hear "エラー" — not the default "読み上げミュート中/有効" labels used
        // on the tappable mute path, which would wrongly suggest a working
        // engine. This asserts the label value, not just icon presence.
        expect(
          find.bySemanticsLabel('読み上げ: エラー'),
          findsOneWidget,
          reason:
              'Android TTS availability failure must expose the ERROR state '
              'via the Semantics label so screen-reader users can also '
              'notice the failure per Issue #682.',
        );
      },
    );

    testWidgets(
      'checkAndroidTtsAvailability throwing surfaces the ERROR icon and does not start speech',
      (WidgetTester tester) async {
        fakePlatform.checkAndroidTtsAvailabilityError = Exception(
          'platform channel failure',
        );

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.checkAndroidTtsAvailabilityCalled, isTrue);
        expect(fakePlatform.startCalled, isFalse);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(find.byIcon(Icons.hourglass_top), findsNothing);
        expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
      },
    );

    testWidgets(
      'Android TTS retries availability check after a prior failure when speech is re-enabled',
      (WidgetTester tester) async {
        // First attempt: availability returns false.
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.checkAndroidTtsAvailabilityCallCount, 1);
        expect(fakePlatform.startCalled, isFalse);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        // User disables speech, then re-enables it — e.g. after going into
        // Android TTS system settings to install Japanese voice data.
        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: false,
            engineType: SpeechEngineType.androidTts,
          ),
        );
        await tester.pumpAndSettle();

        // Second attempt: availability now returns true.
        fakePlatform.androidTtsAvailableToReturn = true;
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: true,
            engineType: SpeechEngineType.androidTts,
          ),
        );
        await tester.pumpAndSettle();

        // The availability check must run AGAIN — retry must be possible
        // after a prior failure. Regression guard for the state-machine
        // concern: a previous attempt set `_speechInitialized=true` on
        // failure, which would have short-circuited the retry and left the
        // user with no way to recover without restarting the app.
        expect(
          fakePlatform.checkAndroidTtsAvailabilityCallCount,
          2,
          reason:
              'The Android TTS availability check must re-run after a prior '
              'failure when the user toggles speech off and on again, so '
              'that recovery (e.g. installing voice data) can take effect '
              'without restarting the app.',
        );
        expect(fakePlatform.startCalled, isTrue);

        // Regression guard: after a successful retry, the ERROR icon from
        // the previous failure must NOT linger. Once `start()` completes the
        // screen transitions engineState ERROR → READY and isStarted=true,
        // which in `_SpeechStatusIcon` should render the `volume_up` icon
        // (not `error_outline`). Without this assertion a future change
        // that forgets to clear `_speechEngineState` on successful init
        // would leave the user with a stale ERROR icon even though speech
        // is actually working.
        expect(
          find.byIcon(Icons.error_outline),
          findsNothing,
          reason:
              'After a successful retry the ERROR icon from the previous '
              'failure must no longer be visible.',
        );
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
      },
    );

    testWidgets(
      'Android TTS availability check is skipped when engine is already READY',
      (WidgetTester tester) async {
        // Simulate a session where VOICEVOX was used first (engine is READY)
        // and the user then switched to Android TTS. The existing pre-check
        // at the top of _initializeAndStartSpeech flips _speechInitialized
        // to true, so the Android TTS branch is bypassed entirely.
        fakePlatform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'READY',
          playerState: 'IDLE',
          queueSize: 0,
          currentSpeakerId: 0,
        );

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.checkAndroidTtsAvailabilityCalled, isFalse);
        expect(fakePlatform.initializeCalled, isFalse);
        expect(fakePlatform.startCalled, isTrue);
      },
    );
  });

  group('mute toggle', () {
    late FakeCommentSpeechPlatform fakePlatform;

    setUp(() {
      fakePlatform = FakeCommentSpeechPlatform();
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

    testWidgets('muted icon shows volume_mute when isSpeechMuted is true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          isSpeechMuted: true,
          onSpeechMuteToggled: () {},
        ),
      );
      await tester.pumpAndSettle();

      final Icon icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('speech-status-icon')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.volume_off);
    });

    testWidgets('non-muted icon shows volume_up when isSpeechMuted is false', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          isSpeechMuted: false,
          onSpeechMuteToggled: () {},
        ),
      );
      await tester.pumpAndSettle();

      final Icon icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('speech-status-icon')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.volume_up);
    });

    testWidgets(
      'tapping mute icon calls onSpeechMuteToggled and shows snackbar',
      (WidgetTester tester) async {
        bool toggled = false;
        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            isSpeechMuted: false,
            onSpeechMuteToggled: () => toggled = true,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('speech-status-icon')));
        await tester.pump();

        expect(toggled, isTrue);
        expect(find.text('ミュートしました'), findsOneWidget);
      },
    );

    testWidgets(
      'mute banner shows volume_off icon when isSpeechMuted is true',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
            isSpeechMuted: true,
            onSpeechMuteToggled: () {},
          ),
        );
        await tester.pumpAndSettle();

        final Finder bannerIcon = find.descendant(
          of: find.byKey(const Key('mute-banner')),
          matching: find.byType(Icon),
        );
        expect(bannerIcon, findsOneWidget);

        final Icon icon = tester.widget<Icon>(bannerIcon);
        expect(icon.icon, Icons.volume_off);
      },
    );

    testWidgets('mute banner is not shown when isSpeechMuted is false', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          isSpeechMuted: false,
          onSpeechMuteToggled: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mute-banner')), findsNothing);
    });

    testWidgets('icon is not tappable when onSpeechMuteToggled is null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          isSpeechMuted: false,
        ),
      );
      await tester.pumpAndSettle();

      // When onSpeechMuteToggled is null, the icon should be a Tooltip
      // (non-tappable), not an IconButton.
      expect(
        find.descendant(
          of: find.byKey(const Key('speech-status-icon')),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
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
    this.slashPrefixSkipEnabled = true,
    this.showUserName = true,
    this.readUserName = false,
    this.readGiftComment = false,
    this.readNicoadComment = false,
    this.userNicknameMap = const <String, String>{},
    this.resolveUserName,
    this.requestUserNameResolve,
    this.isSpeechMuted = false,
    this.onSpeechMuteToggled,
  });

  final List<AppMessage> initialMessages;
  final CommentSpeechPlatform? speechPlatform;
  final SpeechSettings speechSettings;
  final Set<String> ngUserIds;
  final List<String> ngWords;
  final bool starPrefixHidingEnabled;
  final bool slashPrefixSkipEnabled;
  final bool showUserName;
  final bool readUserName;
  final bool readGiftComment;
  final bool readNicoadComment;
  final Map<String, String> userNicknameMap;
  final String? Function(String userId)? resolveUserName;
  final void Function(String userId)? requestUserNameResolve;
  final bool isSpeechMuted;
  final VoidCallback? onSpeechMuteToggled;

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
      programInfo: const CommentProgramInfo(lv: 'lv123456789'),
      connectionSupervisor: _buildStreamingSupervisor(),
      messages: _messages,
      callbacks: CommentCallbacks(
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, _) async {},
        onSpeechMuteToggled: widget.onSpeechMuteToggled,
      ),
      themeMode: AppThemeMode.light,
      showUserName: widget.showUserName,
      userNameResolution: userNameResolution,
      contentFilter: ContentFilterConfig(
        ngUserIds: _ngUserIds,
        ngWords: widget.ngWords,
        starPrefixHidingEnabled: widget.starPrefixHidingEnabled,
        slashPrefixSkipEnabled: widget.slashPrefixSkipEnabled,
        userNicknameMap: widget.userNicknameMap,
      ),
      speechConfig: CommentSpeechConfig(
        speechPlatform: widget.speechPlatform,
        speechSettings: _speechSettings,
        readUserName: widget.readUserName,
        readGiftComment: widget.readGiftComment,
        readNicoadComment: widget.readNicoadComment,
        isSpeechMuted: widget.isSpeechMuted,
      ),
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
  bool slashPrefixSkipEnabled = true,
  bool showUserName = true,
  bool readUserName = false,
  bool readGiftComment = false,
  bool readNicoadComment = false,
  Map<String, String> userNicknameMap = const <String, String>{},
  String? Function(String userId)? resolveUserName,
  void Function(String userId)? requestUserNameResolve,
  bool isSpeechMuted = false,
  VoidCallback? onSpeechMuteToggled,
}) {
  return MaterialApp(
    home: _SpeechTestHost(
      initialMessages: messages,
      speechPlatform: speechPlatform,
      speechSettings: speechSettings,
      ngUserIds: ngUserIds,
      ngWords: ngWords,
      starPrefixHidingEnabled: starPrefixHidingEnabled,
      slashPrefixSkipEnabled: slashPrefixSkipEnabled,
      showUserName: showUserName,
      readUserName: readUserName,
      readGiftComment: readGiftComment,
      readNicoadComment: readNicoadComment,
      userNicknameMap: userNicknameMap,
      resolveUserName: resolveUserName,
      requestUserNameResolve: requestUserNameResolve,
      isSpeechMuted: isSpeechMuted,
      onSpeechMuteToggled: onSpeechMuteToggled,
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
