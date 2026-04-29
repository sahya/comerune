import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/application/speech/speech_availability_notifier.dart';
import 'package:comerune/application/timeline/timeline_store.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/user_name_resolution.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';
import '../../helpers/in_memory_shared_preferences.dart';

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
              // Issue #739: this regression test asserts the legacy
              // immediate-stop behaviour, so disable the grace toggle.
              // The grace path has dedicated tests
              // (broadcast end grace coverage) below.
              playRemainingAfterEnded: false,
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
      'broadcast end with grace ON does not call stop(clearQueue:true) '
      'immediately',
      (WidgetTester tester) async {
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
                // grace defaults to true here.
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.startCalled, isTrue);
        fakePlatform.stopCalled = false;

        expect(supervisor.endBroadcast(), isTrue);
        // Pump short windows; the grace timer is 30s so stop must not fire
        // within these 5s of simulated time.
        await tester.pump(const Duration(seconds: 1));
        expect(fakePlatform.stopCalled, isFalse);
        await tester.pump(const Duration(seconds: 5));
        expect(fakePlatform.stopCalled, isFalse);

        // Tear down — `addTearDown` lets the framework clean up the
        // pending Timer so the test does not flag a leaked timer.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('broadcast end grace stops speech early when queue drains', (
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

      // Broadcast ends → grace timer starts.
      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(fakePlatform.stopCalled, isFalse);

      // Native side reports queue drained → grace should end early.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.queueUpdated,
          payload: <String, dynamic>{'size': 0},
        ),
      );
      await tester.pump();
      expect(
        fakePlatform.stopCalled,
        isTrue,
        reason: 'queue drained during grace must trigger stop()',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'broadcast end grace fires the onSpeechQueueDrained callback when ending',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        int callbackInvocations = 0;

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
                onSpeechQueueDrained: () => callbackInvocations++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(supervisor.endBroadcast(), isTrue);
        await tester.pump(const Duration(seconds: 1));
        expect(callbackInvocations, 0);

        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.queueUpdated,
            payload: <String, dynamic>{'size': 0},
          ),
        );
        await tester.pump();
        expect(
          callbackInvocations,
          1,
          reason: 'onSpeechQueueDrained must fire exactly once on early end',
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('broadcast end grace times out after 30s and stops speech', (
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
      fakePlatform.stopCalled = false;

      expect(supervisor.endBroadcast(), isTrue);
      // Just before timeout: still no stop.
      await tester.pump(const Duration(seconds: 29));
      expect(fakePlatform.stopCalled, isFalse);

      // After timeout: stop fires.
      await tester.pump(const Duration(seconds: 2));
      expect(
        fakePlatform.stopCalled,
        isTrue,
        reason: 'grace timeout must stop speech',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('broadcast end grace cancels on user-driven speech disable', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final ValueNotifier<SpeechSettings> settingsNotifier =
          ValueNotifier<SpeechSettings>(const SpeechSettings(enabled: true));
      addTearDown(settingsNotifier.dispose);

      Widget buildHost(SpeechSettings settings) {
        return MaterialApp(
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
              speechSettings: settings,
            ),
          ),
        );
      }

      await tester.pumpWidget(buildHost(settingsNotifier.value));
      await tester.pumpAndSettle();

      // Enter grace.
      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump(const Duration(seconds: 1));

      // User disables speech mid-grace.
      fakePlatform.stopCalled = false;
      await tester.pumpWidget(buildHost(const SpeechSettings(enabled: false)));
      await tester.pumpAndSettle();
      expect(
        fakePlatform.stopCalled,
        isTrue,
        reason: 'disabling speech mid-grace must stop immediately',
      );

      // 30s pump → no second stop fires (timer was cancelled).
      fakePlatform.stopCalled = false;
      await tester.pump(const Duration(seconds: 31));
      expect(
        fakePlatform.stopCalled,
        isFalse,
        reason: 'grace timer must not fire after cancel',
      );

      await tester.pumpWidget(const SizedBox.shrink());
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

        // Accessibility regression guard: when the icon is in the
        // ERROR branch it must be announced as such by screen readers.
        // After Issue #713 (retry affordance) the label includes
        // "タップで再試行" because the host wires `onRetry`; before #713
        // it used the static '読み上げ: エラー' label. Either form must
        // contain "エラー" so the user hears the failure regardless of
        // whether the icon is currently tappable.
        final Iterable<Element> semanticsCandidates = tester.elementList(
          find.byWidgetPredicate((Widget w) {
            if (w is! Semantics) return false;
            final String? label = w.properties.label;
            return label != null && label.contains('エラー');
          }),
        );
        expect(
          semanticsCandidates,
          isNotEmpty,
          reason:
              'Android TTS availability failure must expose the ERROR state '
              'via the Semantics label so screen-reader users can also '
              'notice the failure per Issue #682. After #713 the label '
              'may also advertise the retry affordance.',
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

  // ---------------------------------------------------------------------------
  // Issue #694: cross-screen Android TTS availability propagation.
  //
  // The TTS settings screen previously kept its check result in local state,
  // so a failure detected there did not flip the AppBar speech-status icon
  // on the comment screen. The fix routes both screens' check results
  // through `SpeechAvailabilityNotifier`; when its value is `unavailable`
  // AND the active engine is Android TTS, the icon must surface ERROR even
  // though the screen's own engineState may still be READY (e.g. the user
  // came back from settings without reconnecting).
  // ---------------------------------------------------------------------------
  group('CommentScreen speech availability notifier (Issue #694)', () {
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

    testWidgets(
      'unavailable notifier flips Android TTS AppBar icon to ERROR after build',
      (WidgetTester tester) async {
        // Reproduces the user flow from Issue #694: AppBar icon is initially
        // happy; user opens TTS settings and the check publishes
        // unavailable; AppBar must update without a reconnect.
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        // Initially the notifier is `unknown` so the icon shows whatever the
        // local engine state says — for the READY fake, that is volume_up.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
        );

        notifier.publishUnavailable();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'When the cross-screen notifier publishes unavailable, the '
              'Android TTS AppBar icon must flip to ERROR without waiting '
              'for the user to reconnect (Issue #694).',
        );
      },
    );

    testWidgets(
      'available publish on the notifier clears a previous unavailable ERROR',
      (WidgetTester tester) async {
        // Recovery flow: user reinstalled Japanese voice data, opened TTS
        // settings, and the re-check now succeeds. The AppBar must follow
        // back to a non-error icon without requiring a reconnect.
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
        notifier.publishUnavailable();

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        // Sanity: starts in ERROR.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );

        notifier.publishAvailable();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'A subsequent available publish must clear the cross-screen '
              'ERROR override (Issue #694).',
        );
      },
    );

    testWidgets(
      'notifier=available clears a stale local _speechEngineState ERROR (cycle-2-new)',
      (WidgetTester tester) async {
        // Cycle-2 (new sage cycle) #704 review: the local ERROR state set
        // by this screen's own failed init must not stay sticky after
        // the cross-screen notifier reports recovery. The icon used to
        // OR `engineState == 'ERROR'` with `notifier.isUnavailable`, so
        // a stale local ERROR kept the AppBar on `error_outline` forever
        // even after settings published `available`.
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
        // Drive the screen down its Android-TTS init path with a check
        // that fails — this sets the local _speechEngineState='ERROR'.
        fakePlatform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'UNINITIALIZED',
          playerState: 'UNKNOWN',
          queueSize: 0,
          currentSpeakerId: 0,
        );
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        // Sanity: local ERROR set, icon is error_outline.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );

        // Now the user goes to TTS settings and the recovery is detected
        // — settings publishes `available` to the notifier.
        notifier.publishAvailable();
        await tester.pump();

        // The AppBar must lift out of ERROR (notifier flipped to available
        // AND the listener cleared the stale local ERROR).
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'A stale local _speechEngineState=ERROR must not keep the '
              'AppBar pinned to ERROR after the cross-screen notifier '
              'publishes recovery (Issue #694 cycle-2-new reverse bug).',
        );
      },
    );

    testWidgets(
      'notifier=available on VOICEVOX engine does NOT clear local ERROR (round-2 engineType gate)',
      (WidgetTester tester) async {
        // Round-2 review #7/#8: without the engineType gate, a stray
        // `available` publish (e.g. during engine swap or from future
        // VOICEVOX-related helpers that share the notifier) would silently
        // clear a *VOICEVOX* ERROR via `_onAndroidTtsAvailabilityChanged`.
        // This test pins the gate by:
        //  1. starting the screen with VOICEVOX engine and a healthy init,
        //  2. pushing engineState='ERROR' via an engineStateChanged event,
        //  3. publishing `available` on the notifier, and
        //  4. asserting the local ERROR persists (gate held).
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.voicevox,
            ),
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        // Push the engine into ERROR via the existing engineStateChanged
        // path (VOICEVOX engine emitting ERROR mid-session).
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.engineStateChanged,
            payload: <String, dynamic>{'state': 'ERROR'},
          ),
        );
        // Drain microtasks for the broadcast stream listener and let the
        // rebuild settle.
        await tester.pump();
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );

        // A stray `available` publish must NOT silently clear this
        // VOICEVOX ERROR — the listener is gated on engineType.
        notifier.publishAvailable();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'A notifier=available publish must not clear a VOICEVOX-side '
              'ERROR — the cross-screen notifier is Android-TTS-specific '
              '(round-2 review).',
        );
      },
    );

    testWidgets(
      'unavailable notifier on VOICEVOX engine does NOT flip the AppBar icon',
      (WidgetTester tester) async {
        // Acceptance criterion: VOICEVOX users must not be affected by the
        // Android-TTS-specific notifier even when it carries a stale value.
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
        notifier.publishUnavailable();

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              // Default is voicevox, but stated explicitly for the reader.
              engineType: SpeechEngineType.voicevox,
            ),
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'VOICEVOX users must not see ERROR on the AppBar just because '
              'the Android-TTS-specific notifier says unavailable (Issue '
              '#694 acceptance criterion).',
        );
      },
    );

    testWidgets(
      'CommentScreen Android-TTS init publishes available to the notifier',
      (WidgetTester tester) async {
        // The screen also publishes back to the notifier so a successful
        // self-check seeds the cross-screen view. This way TTS settings
        // does not have to re-run the platform check on first open.
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
        // Force the screen down its Android-TTS init path by reporting
        // UNINITIALIZED so it actually calls checkAndroidTtsAvailability.
        fakePlatform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'UNINITIALIZED',
          playerState: 'UNKNOWN',
          queueSize: 0,
          currentSpeakerId: 0,
        );
        fakePlatform.androidTtsAvailableToReturn = true;

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          notifier.value,
          SpeechAvailability.available,
          reason:
              'A successful Android TTS check on the comment screen must '
              'publish available to the cross-screen notifier so other '
              'screens see the same view (Issue #694).',
        );
      },
    );

    testWidgets(
      'CommentScreen Android-TTS init publishes unavailable to the notifier on failure',
      (WidgetTester tester) async {
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
        fakePlatform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'UNINITIALIZED',
          playerState: 'UNKNOWN',
          queueSize: 0,
          currentSpeakerId: 0,
        );
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.androidTts,
            ),
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(notifier.value, SpeechAvailability.unavailable);
      },
    );

    testWidgets(
      'cross-screen recovery resets the runtime failure counter (Issue #711 / CR-1)',
      (WidgetTester tester) async {
        // Integration of #694 (notifier) and #695 (failure counter): when
        // the cross-screen notifier publishes available, the runtime
        // failure counter must also be reset to 0. Otherwise after the
        // user re-installs Japanese voice data via TTS settings and the
        // AppBar visibly recovers, a single subsequent transient failure
        // (counter at threshold + 1 = 4 ≥ 3) would re-trip ERROR
        // immediately — an "ERROR rebound" that makes the recovery look
        // ineffective from the user's perspective.
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);
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
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        // Drive the runtime counter to threshold via 3 consecutive
        // android_tts_not_ready events from the native side.
        for (int i = 0; i < 3; i++) {
          fakePlatform.emitEvent(
            const SpeechEvent(
              type: SpeechEventType.speechFailed,
              payload: <String, dynamic>{
                'commentId': 'c-fail',
                'message': 'android_tts_not_ready',
              },
            ),
          );
          await tester.pump();
        }
        await tester.pump();
        // Sanity: ERROR icon is shown.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason: 'Sanity: 3 consecutive failures should have tripped ERROR.',
        );

        // Cross-screen recovery: TTS settings publishes available.
        notifier.publishAvailable();
        await tester.pump();
        await tester.pump();
        // ERROR icon must be gone (#704 listener clears local ERROR).
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason: 'Notifier=available should clear the local ERROR.',
        );

        // Now a single transient failure arrives. WITHOUT the CR-1 fix,
        // the residual counter (= threshold) would push to threshold+1
        // and immediately re-trip ERROR. WITH the fix, the counter was
        // reset on recovery, so a single failure cannot reach threshold.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.speechFailed,
            payload: <String, dynamic>{
              'commentId': 'c-fail-after-recovery',
              'message': 'android_tts_not_ready',
            },
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'Issue #711 / CR-1: cross-screen recovery must reset the '
              'runtime failure counter so a single subsequent transient '
              'failure does not re-trip ERROR.',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Issue #695: Android-TTS runtime degradation must surface to the user.
  //
  // Native already emits `speech_failed` events with reasons
  // `android_tts_not_ready` and `android_tts_failed: <inner>`, but the screen
  // previously only subscribed to `engine_state_changed`, dropping the
  // failure events on the floor. The user saw speech silently stop with no
  // explanation.
  //
  // The fix counts consecutive Android-TTS failures and flips the AppBar
  // icon to ERROR after 3 in a row. A single `speech_completed` resets the
  // counter so a real recovery (OS settings → voice data restored,
  // engine swapped back, etc.) is visible without app restart.
  // ---------------------------------------------------------------------------
  group('CommentScreen speech runtime failure detection (Issue #695)', () {
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

    Future<void> pumpAndSettleSpeech(WidgetTester tester) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Mirror the native payload contract from `SpeechEvents.kt:speechFailed`,
    // which uses `'message'` (not `'reason'`) as the failure description key.
    // Using the wrong key would let the production-broken-but-test-green
    // regression slip through again (Issue #695 cycle-2 review).
    SpeechEvent androidTtsFailure({String message = 'android_tts_not_ready'}) {
      return SpeechEvent(
        type: SpeechEventType.speechFailed,
        payload: <String, dynamic>{'commentId': 'c-fail', 'message': message},
      );
    }

    SpeechEvent speechCompleted() {
      return SpeechEvent(
        type: SpeechEventType.speechCompleted,
        payload: <String, dynamic>{'commentId': 'c-ok'},
      );
    }

    testWidgets(
      'two consecutive android_tts_not_ready failures do NOT flip to ERROR',
      (WidgetTester tester) async {
        // False-positive guard: the threshold must be > 2 so a single CPU
        // spike or transient platform-channel hiccup never alarms the user.
        await pumpAndSettleSpeech(tester);

        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();
        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'Below the failure threshold the AppBar must NOT show ERROR — '
              'isolated transient failures must not alarm the user '
              '(Issue #695).',
        );
      },
    );

    testWidgets(
      'three consecutive android_tts_not_ready failures flip the AppBar to ERROR',
      (WidgetTester tester) async {
        await pumpAndSettleSpeech(tester);

        for (int i = 0; i < 3; i++) {
          fakePlatform.emitEvent(androidTtsFailure());
          await tester.pump();
        }
        // Drain the microtask queue once more in case the failure that
        // crossed the threshold is processed AFTER the last pump (the
        // listener runs in a microtask, and the third emit may be queued
        // behind earlier deliveries).
        await tester.pump();

        // Debug aid for failure investigations: print the actual icon under
        // the AppBar status key. Helps the next reader see immediately why
        // the assertion failed without re-deriving it from the priority
        // logic in `_SpeechStatusIcon`.
        final Iterable<Icon> icons = tester
            .widgetList<Icon>(
              find.descendant(
                of: find.byKey(const Key('speech-status-icon')),
                matching: find.byType(Icon),
              ),
            )
            .toList();
        expect(
          icons.length,
          1,
          reason: 'Status icon should render exactly one Icon child.',
        );
        expect(
          icons.first.icon,
          Icons.error_outline,
          reason:
              'Three consecutive Android TTS failures must be treated as a '
              'real degradation and surfaced via the ERROR icon '
              '(Issue #695). Actual icon: ${icons.first.icon?.codePoint}',
        );
      },
    );

    testWidgets(
      'android_tts_failed:* prefix variants count toward the threshold',
      (WidgetTester tester) async {
        // Native sends `android_tts_failed: <message>` with the inner
        // exception text appended. The fix recognises any reason that
        // starts with `android_tts_failed`, not just an exact match.
        await pumpAndSettleSpeech(tester);

        fakePlatform.emitEvent(
          androidTtsFailure(message: 'android_tts_failed: TTS speak timed out'),
        );
        await tester.pump();
        fakePlatform.emitEvent(
          androidTtsFailure(message: 'android_tts_failed: returned error -1'),
        );
        await tester.pump();
        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a speech_completed in between resets the counter (no false ERROR)',
      (WidgetTester tester) async {
        // Two failures, then a success, then two more failures — total of
        // four failures but only two consecutive. Must NOT trigger ERROR.
        await pumpAndSettleSpeech(tester);

        fakePlatform.emitEvent(androidTtsFailure());
        fakePlatform.emitEvent(androidTtsFailure());
        fakePlatform.emitEvent(speechCompleted());
        fakePlatform.emitEvent(androidTtsFailure());
        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'The counter must reset after a successful speak so '
              'non-consecutive failures do not accumulate into a false '
              'ERROR (Issue #695).',
        );
      },
    );

    testWidgets(
      'engineStateChanged → READY recovery flips the icon back from ERROR',
      (WidgetTester tester) async {
        // Realistic recovery flow: 3 failures push us into ERROR, then
        // native emits engineStateChanged READY (e.g. user reinstalled the
        // Japanese voice data and the engine self-reinitialised). The icon
        // must follow native back to volume_up so the user knows speech is
        // alive again.
        await pumpAndSettleSpeech(tester);

        for (int i = 0; i < 3; i++) {
          fakePlatform.emitEvent(androidTtsFailure());
          await tester.pump();
        }
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );

        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.engineStateChanged,
            payload: <String, dynamic>{'state': 'READY'},
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'A READY engineStateChanged event from native must clear the '
              'ERROR icon — the runtime-failure detection must not pin the '
              'AppBar to ERROR after recovery (Issue #695).',
        );
      },
    );

    testWidgets(
      'speech_completed on VOICEVOX engine does NOT clear an Android-TTS ERROR (round-2)',
      (WidgetTester tester) async {
        // Round-2 review #2/#8: the speechCompleted recovery heuristic
        // must be gated on engineType. A VOICEVOX completion event that
        // races with engine state changes (or arrives during a swap)
        // must not silently clear an Android-TTS ERROR.
        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.voicevox,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Simulate a 'leftover' ERROR (e.g. set by engineStateChanged
        // before swap). Inject by emitting an engineStateChanged='ERROR'.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.engineStateChanged,
            payload: <String, dynamic>{'state': 'ERROR'},
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );

        // VOICEVOX-side speech_completed arrives — this MUST NOT silently
        // flip the engineState back to READY, because the recovery
        // heuristic is gated on engineType=androidTts.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.speechCompleted,
            payload: <String, dynamic>{'commentId': 'voicevox-ok'},
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'A VOICEVOX speech_completed must not clear ERROR — the '
              'recovery heuristic is gated on engineType=androidTts '
              '(Issue #695 round-2 review).',
        );
      },
    );

    testWidgets(
      'speech_completed clears the ERROR state and the AppBar recovers (cycle-2-new, Android TTS)',
      (WidgetTester tester) async {
        // Cycle-2 (new sage cycle) #705 review: native does not emit a
        // runtime engineStateChanged → READY for Android TTS, only at
        // initialize. Without `speech_completed` flipping the engine state
        // back to READY, the AppBar is a one-way trap: once threshold is
        // tripped, the icon stays on `error_outline` until app restart.
        //
        // Round-2 update: this recovery is gated on engineType=androidTts
        // so a VOICEVOX completion that races with a swap cannot silently
        // clear an Android TTS ERROR (covered by a sibling test).
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
        for (int i = 0; i < 3; i++) {
          fakePlatform.emitEvent(androidTtsFailure());
          await tester.pump();
        }
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason: 'Sanity: 3 consecutive failures should have tripped ERROR.',
        );

        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.speechCompleted,
            payload: <String, dynamic>{'commentId': 'c-ok'},
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'A single successful speech_completed must lift the AppBar '
              'out of ERROR — without this recovery path the runtime '
              'failure detection becomes a one-way trap (Issue #695 '
              'cycle-2-new review).',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.volume_up),
          ),
          findsOneWidget,
          reason:
              'After recovery the icon must return to volume_up so the '
              'user sees that speech is working again.',
        );
      },
    );

    testWidgets(
      'engineStateChanged → READY also resets the failure counter (cycle-3)',
      (WidgetTester tester) async {
        // Cycle-3 review #8: without the counter reset, a single transient
        // failure right after recovery would push the count from
        // (threshold) to (threshold+1), tripping ERROR again immediately.
        await pumpAndSettleSpeech(tester);

        // Drive the counter to threshold so the screen is in ERROR.
        for (int i = 0; i < 3; i++) {
          fakePlatform.emitEvent(androidTtsFailure());
          await tester.pump();
        }
        await tester.pump();
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );

        // Native recovery — engineStateChanged READY arrives.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.engineStateChanged,
            payload: <String, dynamic>{'state': 'READY'},
          ),
        );
        await tester.pump();
        await tester.pump();

        // A single subsequent failure must NOT push us back into ERROR — the
        // READY transition reset the counter so we are far below threshold.
        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'A single failure right after a READY recovery must not '
              'immediately re-trigger ERROR — the counter must have been '
              'reset on the READY transition (Issue #695 cycle-3 review).',
        );
      },
    );

    testWidgets(
      'voicevox_synthesis_failed reasons do NOT increment the Android-TTS counter',
      (WidgetTester tester) async {
        // Defensive: only Android-TTS failure reasons must move the counter.
        // A flood of VOICEVOX synthesis failures (different code path) must
        // not accidentally flip the Android-TTS-targeted ERROR icon.
        await pumpAndSettleSpeech(tester);

        for (int i = 0; i < 10; i++) {
          fakePlatform.emitEvent(
            androidTtsFailure(message: 'voicevox_synthesis_failed: code 42'),
          );
        }
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'VOICEVOX failure reasons must not contribute to the Android '
              'TTS failure counter — they have their own code path '
              '(Issue #695).',
        );
      },
    );

    testWidgets(
      'switching engine type resets the failure counter to avoid carry-over ERROR',
      (WidgetTester tester) async {
        // Two failures on Android TTS, then user switches to VOICEVOX, then
        // back to Android TTS. The carry-over counter must NOT push the new
        // session straight into ERROR on the very first failure
        // (Issue #695 review #8).
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

        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();
        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        // Switch to VOICEVOX (engine-type change resets the counter).
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: true,
            engineType: SpeechEngineType.voicevox,
          ),
        );
        await tester.pumpAndSettle();
        // Switch back to Android TTS.
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: true,
            engineType: SpeechEngineType.androidTts,
          ),
        );
        await tester.pumpAndSettle();

        // A single fresh failure must NOT trip ERROR — the prior counter
        // from the earlier session was reset on engine-type change.
        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'Engine-type change must reset the failure counter so a new '
              'session does not inherit the previous engine\'s failures '
              '(Issue #695 review).',
        );
      },
    );

    testWidgets(
      'realistic native messages with prefixed exception text count toward the threshold (Issue #695 cycle-2)',
      (WidgetTester tester) async {
        // Cycle-2 contract guard: the native side now wraps every Android
        // TTS speak failure with the `android_tts_failed:` prefix
        // (see SpeechControllerImpl.processWithAndroidTts). Realistic
        // values include arbitrary inner exception text. The detector must
        // recognise these as Android TTS failures.
        await pumpAndSettleSpeech(tester);

        const List<String> realisticFailures = <String>[
          'android_tts_failed: TTS speak() returned error: -1',
          'android_tts_failed: TTS speak timed out',
          'android_tts_failed: unknown',
        ];
        for (final String message in realisticFailures) {
          fakePlatform.emitEvent(androidTtsFailure(message: message));
          await tester.pump();
        }
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'Realistic prefixed Android-TTS failure messages must trip '
              'the threshold — without the cycle-2 fix the detector read '
              'the wrong payload key and never observed any failures '
              '(Issue #695 cycle-2 review).',
        );
      },
    );

    testWidgets(
      'malformed payload does not crash the listener (defensive cast guard)',
      (WidgetTester tester) async {
        // Defensive regression: a non-String `reason` (or a missing key,
        // or a non-Map payload field) must not throw inside the listener.
        // If it did, the StreamSubscription would tear down and silently
        // break all future event delivery (Issue #695 review #7).
        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
          ),
        );
        await tester.pumpAndSettle();

        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.speechFailed,
            payload: <String, dynamic>{'commentId': 1, 'message': 42},
          ),
        );
        await tester.pump();
        // After the malformed event, normal events must still be processed
        // — confirming the subscription is alive.
        for (int i = 0; i < 3; i++) {
          fakePlatform.emitEvent(androidTtsFailure());
          await tester.pump();
        }
        await tester.pump();

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'After a malformed speech_failed payload the listener must '
              'still react to subsequent valid failures (Issue #695 '
              'review #7).',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Issue #696: VOICEVOX setup failure / cancellation must surface ERROR.
  // Without the fix, the AppBar stayed on the neutral hourglass icon even
  // after the user cancelled the setup dialog, making cancellation
  // indistinguishable from "still initialising" and hiding that the engine
  // actually entered an ERROR state on the native side.
  // ---------------------------------------------------------------------------
  group('CommentScreen speech integration (VOICEVOX setup failure)', () {
    late FakeCommentSpeechPlatform fakePlatform;

    setUp(() {
      fakePlatform = FakeCommentSpeechPlatform();
    });

    tearDown(() {
      fakePlatform.dispose();
    });

    testWidgets(
      'VOICEVOX setup dialog cancellation surfaces ERROR icon on the AppBar',
      (WidgetTester tester) async {
        // Engine is NOT ready, so the screen will open VoicevoxSetupDialog.
        fakePlatform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'UNINITIALIZED',
          playerState: 'IDLE',
          queueSize: 0,
          currentSpeakerId: 0,
        );
        // Force the setup helper to fail immediately so the dialog exposes
        // its "閉じる" (close) button. Tapping it pops the dialog with `false`,
        // which is the cancellation path Issue #696 targets.
        fakePlatform.initializeError = Exception(
          'simulated VOICEVOX init failure',
        );

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
          ),
        );
        await tester.pumpAndSettle();

        // The dialog is open and shows the close button — tap it to cancel.
        expect(find.text('閉じる'), findsOneWidget);
        await tester.tap(find.text('閉じる'));
        await tester.pumpAndSettle();

        // After cancellation the AppBar's status icon must show ERROR. Without
        // the fix it stayed on `hourglass_top` ("初期化中"), which Issue #696
        // calls out as the user-visible bug.
        expect(find.byKey(const Key('speech-status-icon')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'After VOICEVOX setup is cancelled the AppBar must surface the '
              'ERROR icon so the user can distinguish failure from "still '
              'initialising" (Issue #696).',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.hourglass_top),
          ),
          findsNothing,
          reason:
              'The hourglass ("初期化中") icon must NOT remain after a cancelled '
              'VOICEVOX setup — that was the bug reported in Issue #696.',
        );
        // start() must NOT have been called: setup never completed, so the
        // worker loop must not run against an un-ready engine.
        expect(fakePlatform.startCalled, isFalse);
      },
    );

    testWidgets(
      'VOICEVOX engine returning ERROR from getStatus surfaces ERROR icon while dialog is pending',
      (WidgetTester tester) async {
        // Native engine is already in ERROR (e.g. a previous setup attempt
        // failed and the user is opening a new program). Issue #696 calls out
        // that the screen previously ignored this engineState and kept the
        // hourglass icon while re-showing the setup dialog.
        fakePlatform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'ERROR',
          playerState: 'IDLE',
          queueSize: 0,
          currentSpeakerId: 0,
        );
        // Block the setup helper at `initialize()` so the dialog stays open.
        // This isolates the assertion to the getStatus → ERROR setState path
        // added by the fix; without the gate the dialog would resolve to
        // ready and the screen would overwrite engineState back to READY,
        // hiding the regression.
        fakePlatform.initializeCompleter = Completer<void>();

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
          ),
        );
        // Pump (without settle) until the dialog is in flight — pumpAndSettle
        // would hang because initialize is gated.
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        // While the dialog is still up, the AppBar's status icon must already
        // reflect the ERROR engineState reported by getStatus().
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'getStatus() reporting ERROR must immediately propagate to the '
              'AppBar icon, even while the setup dialog is still visible '
              '(Issue #696).',
        );

        // Release the gate so the dialog can complete and the test can tear
        // down cleanly without leaving timers / streams pending.
        fakePlatform.initializeCompleter!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'VOICEVOX engine: getStatus throwing surfaces ERROR icon while dialog is pending (round-2)',
      (WidgetTester tester) async {
        // Round-2 review: in addition to the explicit
        // `engineState == 'ERROR'` path, a thrown getStatus must also flip
        // the AppBar to ERROR — both are "engine not usable" signals from
        // the user's perspective, and the symmetric handling closes the
        // hourglass-stuck regression.
        fakePlatform.getStatusError = Exception('platform channel failure');
        fakePlatform.initializeCompleter = Completer<void>();

        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
          ),
        );
        for (int i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
          reason:
              'A thrown getStatus must surface ERROR symmetrically with '
              'the explicit ERROR engineState path (Issue #696 round-2 '
              'review).',
        );

        fakePlatform.initializeCompleter!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'getStatus reporting READY after a stale ERROR clears the local engineState (post-merge round-2)',
      (WidgetTester tester) async {
        // Post-merge round-2 review: a previous init attempt may have set
        // `_speechEngineState='ERROR'` (e.g. from getStatus returning
        // ERROR or from a cancelled setup dialog). On the next init
        // attempt, if getStatus now reports READY, the local ERROR must
        // be cleared so the AppBar icon does not stay on `error_outline`
        // even though the engine is actually ready. Without this clear,
        // the icon priority logic (ERROR first) would mask a recovered
        // engine until start() finally lands.
        //
        // Construct a sequence where the FIRST getStatus call returns
        // ERROR (fakePlatform's status is ERROR), then we re-emit READY
        // for the SECOND call — but for simplicity we directly seed
        // ERROR via the fakePlatform's status and assert that on a
        // *single* init the next-step start() success eventually clears
        // the icon back to volume_up. This pins the post-merge fix that
        // also clears ERROR when the engine is freshly READY at status
        // time.
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
            speechSettings: const SpeechSettings(enabled: true),
          ),
        );
        await tester.pumpAndSettle();

        // Engine reports READY at startup → no ERROR, icon is volume_up.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.volume_up),
          ),
          findsOneWidget,
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // Issue #712 (UX-1): SnackBar fired on the transition INTO an ERROR
  // engine state. Already-in-ERROR re-entries during the same episode
  // must not re-fire (avoids spam). A fresh READY→ERROR cycle does fire.
  // ---------------------------------------------------------------------
  group('CommentScreen speech ERROR SnackBar notification (Issue #712)', () {
    late FakeCommentSpeechPlatform fakePlatform;
    late SharedPreferencesSettingsStore settingsStore;

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

    Future<void> pumpReady(WidgetTester tester) async {
      settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
          settingsStore: settingsStore,
        ),
      );
      await tester.pumpAndSettle();
    }

    SpeechEvent engineState(String state) {
      return SpeechEvent(
        type: SpeechEventType.engineStateChanged,
        payload: <String, dynamic>{'state': state},
      );
    }

    Future<void> pumpEvent(WidgetTester tester, SpeechEvent event) async {
      fakePlatform.emitEvent(event);
      await tester.pump();
      // The SnackBar is queued via WidgetsBinding.addPostFrameCallback
      // and needs an additional frame + the SnackBar's enter animation
      // to materialize into the widget tree. pumpAndSettle drains both.
      await tester.pumpAndSettle();
    }

    int countErrorSnackBars(WidgetTester tester) {
      return tester
          .widgetList<SnackBar>(find.byKey(const Key('speech-error-snackbar')))
          .length;
    }

    testWidgets('READY → ERROR transition shows the SnackBar exactly once', (
      WidgetTester tester,
    ) async {
      await pumpReady(tester);

      await pumpEvent(tester, engineState('ERROR'));

      expect(
        countErrorSnackBars(tester),
        1,
        reason:
            'A single READY → ERROR transition must surface exactly one '
            'SnackBar. Issue #712 asks for active notification on first '
            'failure detection.',
      );
      expect(find.text('読み上げエンジンでエラーが発生しました'), findsOneWidget);
      expect(find.text('設定を開く'), findsOneWidget);
    });

    testWidgets(
      'subsequent ERROR while still in ERROR does NOT re-fire (idempotent)',
      (WidgetTester tester) async {
        await pumpReady(tester);

        await pumpEvent(tester, engineState('ERROR'));
        // Second engineStateChanged with the same value is a no-op
        // for the setter (`prev == next`), but even if a different
        // path re-asserts ERROR mid-episode, the
        // `_speechErrorNotified` flag suppresses duplicates.
        await pumpEvent(tester, engineState('ERROR'));

        expect(
          countErrorSnackBars(tester),
          1,
          reason:
              'ERROR re-entry within the same episode must not spam '
              'additional SnackBars.',
        );
      },
    );

    testWidgets(
      'READY → ERROR → READY → ERROR shows the SnackBar twice (one per fresh episode)',
      (WidgetTester tester) async {
        await pumpReady(tester);

        await pumpEvent(tester, engineState('ERROR'));
        // Dismiss the first SnackBar so the second one's appearance is
        // observable cleanly.
        ScaffoldMessenger.of(
          tester.element(find.byKey(const Key('speech-error-snackbar'))),
        ).removeCurrentSnackBar();
        await tester.pump();

        await pumpEvent(tester, engineState('READY'));
        await pumpEvent(tester, engineState('ERROR'));

        expect(
          countErrorSnackBars(tester),
          1,
          reason:
              'After ERROR → READY → ERROR, the second ERROR must fire '
              'a fresh SnackBar (we dismissed the first one explicitly '
              'so the messenger has a clean slate).',
        );
      },
    );

    testWidgets('tapping "設定を開く" navigates to TtsSettingsScreen', (
      WidgetTester tester,
    ) async {
      await pumpReady(tester);
      await pumpEvent(tester, engineState('ERROR'));

      await tester.tap(find.text('設定を開く'));
      await tester.pumpAndSettle();

      // The TtsSettingsScreen renders the read-aloud settings list with
      // a known list key.
      expect(
        find.byKey(const Key('tts-settings-list')),
        findsOneWidget,
        reason:
            'The SnackBar action must push TtsSettingsScreen onto the '
            'navigator (Issue #712).',
      );
    });

    testWidgets(
      'unknown engineState wires (defensive default) do NOT trigger the SnackBar',
      (WidgetTester tester) async {
        // Native is allowed to extend the wire format; unrecognised
        // strings remain non-ERROR and must not produce a SnackBar.
        await pumpReady(tester);
        await pumpEvent(tester, engineState('UNINITIALIZED'));
        await pumpEvent(tester, engineState('busy'));

        expect(countErrorSnackBars(tester), 0);
      },
    );
  });

  // ---------------------------------------------------------------------
  // Issue #713 (UX-2): tappable-icon retry affordance in ERROR state.
  // The mute toggle is intentionally disabled in ERROR (see canToggleMute);
  // when an `onRetry` callback is wired, the icon must instead become a
  // re-init button so the user can recover without leaving the screen.
  // ---------------------------------------------------------------------
  group('CommentScreen speech ERROR retry affordance (Issue #713)', () {
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

    Future<void> pumpAndSettleSpeech(WidgetTester tester) async {
      await tester.pumpWidget(
        _buildScreen(
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();
    }

    SpeechEvent androidTtsFailure({String message = 'android_tts_not_ready'}) {
      return SpeechEvent(
        type: SpeechEventType.speechFailed,
        payload: <String, dynamic>{'commentId': 'c-fail', 'message': message},
      );
    }

    Future<void> driveIntoError(WidgetTester tester) async {
      // Reuse the existing 3-strike runtime-failure path to push the
      // engine into ERROR state.
      await pumpAndSettleSpeech(tester);
      for (int i = 0; i < 3; i++) {
        fakePlatform.emitEvent(androidTtsFailure());
        await tester.pump();
      }
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('speech-status-icon')),
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
        reason: 'precondition: engine should be in ERROR after 3 failures',
      );
    }

    testWidgets(
      'ERROR state exposes a tappable retry IconButton (key + Semantics)',
      (WidgetTester tester) async {
        await driveIntoError(tester);

        // The retry IconButton has its own dedicated key so widget tests
        // can assert tappability without confusing it with the mute
        // IconButton (which is hidden in ERROR).
        expect(
          find.byKey(const Key('speech-status-icon-retry')),
          findsOneWidget,
        );

        // Tooltip should advertise the retry affordance in plain text.
        expect(find.byTooltip('読み上げ: エラー（タップで再試行）'), findsOneWidget);
      },
    );

    testWidgets(
      'READY state does NOT expose the retry IconButton (mute toggle owns the icon)',
      (WidgetTester tester) async {
        // Engine starts READY (statusToReturn). The icon should be a
        // mute-toggle, not a retry button.
        await pumpAndSettleSpeech(tester);
        expect(find.byKey(const Key('speech-status-icon-retry')), findsNothing);
        // And the running icon (volume_up) is shown.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.volume_up),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping the retry IconButton in ERROR triggers re-initialisation '
      '(driving the engine through READY) and clears the ERROR icon',
      (WidgetTester tester) async {
        // Pre-drive into ERROR.
        await driveIntoError(tester);

        // Tap the retry icon.
        await tester.tap(find.byKey(const Key('speech-status-icon-retry')));
        await tester.pump();
        await tester.pumpAndSettle();

        // The host's `_initializeAndStartSpeech` runs through the fake
        // platform, which has `engineState: 'READY'` in `statusToReturn`.
        // After re-init, `_speechEngineState` should transition back to
        // ready / unknown via the start() success path, clearing the
        // error_outline icon.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
          reason:
              'After retry succeeds, the icon must leave ERROR state '
              '(otherwise the user sees no acknowledgement of their '
              'recovery action — same UX as the original "stuck on '
              'ERROR" complaint that motivated #713).',
        );
      },
    );

    testWidgets('tapping the retry IconButton fires HapticFeedback.lightImpact '
        '(parity with the mute toggle UX)', (WidgetTester tester) async {
      // Capture the platform channel calls so we can assert that the
      // haptic feedback fires on retry. Mirrors the mute-toggle UX
      // contract (mute toggle also fires lightImpact on press).
      final List<MethodCall> platformCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await driveIntoError(tester);

      // Clear any platform calls accumulated during ERROR setup.
      platformCalls.clear();

      await tester.tap(find.byKey(const Key('speech-status-icon-retry')));
      await tester.pump();

      // HapticFeedback.lightImpact() invokes
      // SystemChannels.platform.invokeMethod('HapticFeedback.vibrate',
      // 'HapticFeedbackType.lightImpact').
      final bool didFireHaptic = platformCalls.any(
        (MethodCall c) =>
            c.method == 'HapticFeedback.vibrate' &&
            c.arguments == 'HapticFeedbackType.lightImpact',
      );
      expect(
        didFireHaptic,
        isTrue,
        reason:
            'retry tap must fire HapticFeedback.lightImpact, '
            'matching the mute-toggle UX. Captured: $platformCalls',
      );
    });

    testWidgets(
      'rapid double-tap on the retry IconButton does NOT re-enter init '
      'concurrently (existing _speechInitializing guard)',
      (WidgetTester tester) async {
        // Inject a slow getStatus to keep `_speechInitializing` true
        // long enough for the double-tap window. We cannot directly
        // observe the in-flight init from here, but we CAN observe
        // that the system stays consistent (no exceptions, no extra
        // error_outline flicker) and the eventual outcome is a single
        // recovered state.
        await driveIntoError(tester);

        // Double-tap quickly.
        await tester.tap(find.byKey(const Key('speech-status-icon-retry')));
        await tester.tap(find.byKey(const Key('speech-status-icon-retry')));
        await tester.pump();
        await tester.pumpAndSettle();

        // The system must converge — exactly the same final state as
        // the single-tap test above.
        expect(
          find.descendant(
            of: find.byKey(const Key('speech-status-icon')),
            matching: find.byIcon(Icons.error_outline),
          ),
          findsNothing,
        );
      },
    );
  });

  group('CommentScreen engine type switch (issue #734)', () {
    late FakeCommentSpeechPlatform fakePlatform;

    setUp(() {
      fakePlatform = FakeCommentSpeechPlatform();
      // Engine already ready so the setup dialog is not shown.
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

    testWidgets(
      'switching engineType (androidTts → voicevox) re-initializes engine',
      (WidgetTester tester) async {
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

        // Initial init+start completed for Android TTS.
        expect(fakePlatform.startCalled, isTrue);
        expect(fakePlatform.stopCalled, isFalse);
        final int updateCallsBeforeSwitch =
            fakePlatform.updateSettingsCalls.length;
        expect(updateCallsBeforeSwitch, greaterThanOrEqualTo(1));

        // Reset trackers to observe what happens on the engine switch.
        fakePlatform.startCalled = false;
        fakePlatform.stopCalled = false;

        // Switch to Voicevox.
        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: true,
            engineType: SpeechEngineType.voicevox,
          ),
        );
        await tester.pumpAndSettle();

        // Re-init flow must run: stop → updateSettings → start.
        expect(
          fakePlatform.stopCalled,
          isTrue,
          reason: 'stop() must be called before re-initializing',
        );
        expect(
          fakePlatform.startCalled,
          isTrue,
          reason: 'start() must be called for the new engine',
        );
        expect(
          fakePlatform.updateSettingsCalls.length,
          greaterThan(updateCallsBeforeSwitch),
          reason: 'updateSettings must be called with the new engineType',
        );
        expect(
          fakePlatform.lastUpdatedSettings?.engineType,
          SpeechEngineType.voicevox,
        );
      },
    );

    testWidgets(
      'switching engineType (voicevox → androidTts) re-initializes engine',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: true,
              engineType: SpeechEngineType.voicevox,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.startCalled, isTrue);
        fakePlatform.startCalled = false;
        fakePlatform.stopCalled = false;
        final int updateCallsBeforeSwitch =
            fakePlatform.updateSettingsCalls.length;

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: true,
            engineType: SpeechEngineType.androidTts,
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.stopCalled, isTrue);
        expect(fakePlatform.startCalled, isTrue);
        expect(
          fakePlatform.updateSettingsCalls.length,
          greaterThan(updateCallsBeforeSwitch),
        );
        expect(
          fakePlatform.lastUpdatedSettings?.engineType,
          SpeechEngineType.androidTts,
        );
      },
    );

    testWidgets(
      'engineType switch with disabled=true→true does not start the new engine',
      (WidgetTester tester) async {
        // Speech is disabled to begin with — no init runs.
        await tester.pumpWidget(
          _buildScreen(
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(
              enabled: false,
              engineType: SpeechEngineType.androidTts,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakePlatform.startCalled, isFalse);

        // Switch engineType while still disabled.
        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: false,
            engineType: SpeechEngineType.voicevox,
          ),
        );
        await tester.pumpAndSettle();

        // No start should be triggered when newSettings.enabled is false.
        expect(fakePlatform.startCalled, isFalse);
        expect(fakePlatform.stopCalled, isFalse);
      },
    );

    testWidgets(
      'switching engineType resets _speechInitialized so getStatus runs again',
      (WidgetTester tester) async {
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

        // Initial init: getStatus is called once at startup.
        final int statusCallsAfterInit = fakePlatform.getStatusCallCount;
        expect(statusCallsAfterInit, greaterThanOrEqualTo(1));

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );
        host.updateSpeechSettings(
          const SpeechSettings(
            enabled: true,
            engineType: SpeechEngineType.voicevox,
          ),
        );
        await tester.pumpAndSettle();

        // Because _speechInitialized was reset, the re-init path calls
        // getStatus again to (re)check engine state for the new engine.
        expect(
          fakePlatform.getStatusCallCount,
          greaterThan(statusCallsAfterInit),
          reason:
              '_speechInitialized must be reset so the re-init path checks status again',
        );
      },
    );

    testWidgets(
      'repeated engineType toggling continues to re-initialize each time',
      (WidgetTester tester) async {
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

        final _SpeechTestHostState host = tester.state(
          find.byType(_SpeechTestHost),
        );

        const List<String> sequence = <String>[
          SpeechEngineType.voicevox,
          SpeechEngineType.androidTts,
          SpeechEngineType.voicevox,
          SpeechEngineType.androidTts,
          SpeechEngineType.voicevox,
        ];

        int previousStartCount = 1;
        for (final String engineType in sequence) {
          fakePlatform.startCalled = false;
          host.updateSpeechSettings(
            SpeechSettings(enabled: true, engineType: engineType),
          );
          await tester.pumpAndSettle();
          expect(
            fakePlatform.startCalled,
            isTrue,
            reason: 'start() must be called for engineType=$engineType',
          );
          expect(fakePlatform.lastUpdatedSettings?.engineType, engineType);
          previousStartCount++;
        }
        expect(previousStartCount, sequence.length + 1);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Issue #758: background poll timer reads latest TimelineStore snapshot.
  //
  // In foreground the widget tree rebuild cycle pushes the latest
  // `messages` snapshot into `widget.messages` via didUpdateWidget, and the
  // existing tests cover that path. When the activity is backgrounded the
  // Flutter engine pauses frame scheduling, so didUpdateWidget never fires
  // and `widget.messages` becomes stale. The poll timer is the only safety
  // net, and it must read the latest snapshot directly from the
  // TimelineStore to detect new arrivals while in bg.
  // -------------------------------------------------------------------------
  group('CommentScreen background poll timer (Issue #758)', () {
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

    testWidgets('bg lifecycle: TimelineStore mutation submits via poll timer', (
      WidgetTester tester,
    ) async {
      final TimelineStore store = TimelineStore(capacity: 100);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        _buildBgPollScreen(
          timelineStore: store,
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(fakePlatform.startCalled, isTrue);

      // Simulate going to background. didUpdateWidget will not fire on the
      // CommentScreen anymore for any TimelineStore mutation we make.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // New comment arrives while in bg. widget.messages is the empty
      // snapshot captured at the last build, so without the fix the
      // poll timer would never detect this.
      store.add(_chatMessage(id: 'bg-1', content: 'バックグラウンド'));

      // Poll timer is Timer.periodic(2 seconds). Advancing the test
      // clock by slightly more than 2s lets it fire once.
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));

      expect(fakePlatform.submittedComments, hasLength(1));
      expect(fakePlatform.submittedComments.first.text, 'バックグラウンド');

      // Drain pending timers before the test ends.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    testWidgets('dispose cancels bg poll timer (no submit after teardown)', (
      WidgetTester tester,
    ) async {
      // Verifies the timer is cancelled in dispose. Regardless of fg/bg,
      // a disposed CommentScreen must not submit any further comments.
      final TimelineStore store = TimelineStore(capacity: 100);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        _buildBgPollScreen(
          timelineStore: store,
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();

      // Dispose the screen by replacing it with an empty widget tree.
      // Stay in resumed state so pumpWidget actually unmounts (paused
      // state pauses frame scheduling and would queue the dispose).
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      final int submitsBeforeMutation = fakePlatform.submittedComments.length;

      // Move to background and mutate the store. If the timer was leaked
      // the submit path would still fire.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      store.add(_chatMessage(id: 'after-dispose-1', content: 'もう死んでる'));
      await tester.pump(const Duration(seconds: 3));

      expect(
        fakePlatform.submittedComments.length,
        submitsBeforeMutation,
        reason:
            'No new submit must occur after CommentScreen.dispose(); '
            'the bg poll timer must be cancelled.',
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    testWidgets(
      'fg→disable→bg: poll does not submit after speech is disabled',
      (WidgetTester tester) async {
        // Real-world flow: settings UI is touched in fg, so the disable
        // path runs while resumed (didUpdateWidget fires). Then we bg and
        // verify the poll path stays silent.
        final TimelineStore store = TimelineStore(capacity: 100);
        addTearDown(store.dispose);

        await tester.pumpWidget(
          _buildBgPollScreen(
            timelineStore: store,
            speechPlatform: fakePlatform,
            speechSettings: const SpeechSettings(enabled: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(fakePlatform.startCalled, isTrue);

        // Disable speech in foreground (typical UI path).
        final _BgPollHostState host = tester.state(find.byType(_BgPollHost));
        host.updateSpeechSettings(const SpeechSettings(enabled: false));
        await tester.pumpAndSettle();
        expect(fakePlatform.stopCalled, isTrue);

        // Now go to bg and add a comment — the poll path must NOT submit
        // because speech is disabled and the timer is cancelled.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();

        store.add(_chatMessage(id: 'disabled-1', content: '無音'));
        await tester.pump(const Duration(seconds: 3));

        expect(fakePlatform.submittedComments, isEmpty);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets('bg → fg → bg cycle preserves cursor (no duplicate submit)', (
      WidgetTester tester,
    ) async {
      final TimelineStore store = TimelineStore(capacity: 100);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        _buildBgPollScreen(
          timelineStore: store,
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();

      // Phase 1: bg, add a comment, poll fires and submits.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      store.add(_chatMessage(id: 'cycle-bg-1', content: 'one'));
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));
      expect(fakePlatform.submittedComments, hasLength(1));

      // Phase 2: resume → fg path (didUpdateWidget) on next host setState.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // Push the latest snapshot into widget.messages explicitly via the
      // host (mirrors how SelectScreen rebuilds on store notification).
      final _BgPollHostState host = tester.state(find.byType(_BgPollHost));
      host.syncFromStore();
      await tester.pumpAndSettle();
      // No new comment in fg, no extra submit.
      expect(fakePlatform.submittedComments, hasLength(1));

      // Phase 3: bg again, add another comment.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      store.add(_chatMessage(id: 'cycle-bg-2', content: 'two'));
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));

      // Only the new comment is submitted; the cursor prevented re-submit
      // of cycle-bg-1.
      expect(fakePlatform.submittedComments, hasLength(2));
      expect(fakePlatform.submittedComments.last.text, 'two');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    testWidgets('multiple bg mutations all submit on next poll', (
      WidgetTester tester,
    ) async {
      final TimelineStore store = TimelineStore(capacity: 100);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        _buildBgPollScreen(
          timelineStore: store,
          speechPlatform: fakePlatform,
          speechSettings: const SpeechSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // Three comments arrive in close succession during bg.
      store.add(_chatMessage(id: 'multi-1', content: 'A'));
      store.add(_chatMessage(id: 'multi-2', content: 'B'));
      store.add(_chatMessage(id: 'multi-3', content: 'C'));

      // One poll cycle should drain all three (they are after the cursor).
      await tester.pump(const Duration(seconds: 2, milliseconds: 100));

      expect(fakePlatform.submittedComments, hasLength(3));
      expect(
        fakePlatform.submittedComments.map((RawComment c) => c.text).toList(),
        <String>['A', 'B', 'C'],
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Helpers for Issue #758 background poll tests
// ---------------------------------------------------------------------------

/// Hosts a [CommentScreen] wired to a real [TimelineStore] so the bg poll
/// timer can pick up store mutations. Distinct from [_SpeechTestHost] to
/// keep the bg-specific scaffolding isolated and easy to read.
class _BgPollHost extends StatefulWidget {
  const _BgPollHost({
    required this.timelineStore,
    required this.speechPlatform,
    required this.speechSettings,
  });

  final TimelineStore timelineStore;
  final CommentSpeechPlatform? speechPlatform;
  final SpeechSettings speechSettings;

  @override
  State<_BgPollHost> createState() => _BgPollHostState();
}

class _BgPollHostState extends State<_BgPollHost> {
  late SpeechSettings _speechSettings;
  late List<AppMessage> _messages;
  // Cache the supervisor across rebuilds so didUpdateWidget detects identity
  // stability — otherwise CommentScreen would treat every rebuild as a new
  // connection and re-init speech, masking the bg poll path under test.
  late final ConnectionSupervisor _supervisor = _buildStreamingSupervisor();

  @override
  void initState() {
    super.initState();
    _speechSettings = widget.speechSettings;
    _messages = widget.timelineStore.messages.toList(growable: false);
  }

  @override
  void dispose() {
    _supervisor.dispose();
    super.dispose();
  }

  void updateSpeechSettings(SpeechSettings settings) {
    setState(() {
      _speechSettings = settings;
    });
  }

  /// Mirrors the SelectScreen behaviour of forwarding the latest store
  /// snapshot to widget.messages via a rebuild. Used to verify cursor
  /// behaviour across bg → fg → bg transitions.
  void syncFromStore() {
    setState(() {
      _messages = widget.timelineStore.messages.toList(growable: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CommentScreen(
      programInfo: const CommentProgramInfo(lv: 'lv123456789'),
      connectionSupervisor: _supervisor,
      messages: _messages,
      callbacks: CommentCallbacks(
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, _) async {},
      ),
      themeMode: AppThemeMode.light,
      speechConfig: CommentSpeechConfig(
        speechPlatform: widget.speechPlatform,
        speechSettings: _speechSettings,
        timelineStore: widget.timelineStore,
      ),
    );
  }
}

Widget _buildBgPollScreen({
  required TimelineStore timelineStore,
  FakeCommentSpeechPlatform? speechPlatform,
  SpeechSettings speechSettings = const SpeechSettings(enabled: true),
}) {
  return MaterialApp(
    home: _BgPollHost(
      timelineStore: timelineStore,
      speechPlatform: speechPlatform,
      speechSettings: speechSettings,
    ),
  );
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
    this.androidTtsAvailability,
    this.settingsStore,
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
  final SpeechAvailabilityNotifier? androidTtsAvailability;
  final SettingsStore? settingsStore;

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
        androidTtsAvailability: widget.androidTtsAvailability,
        settingsStore: widget.settingsStore,
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
  SpeechAvailabilityNotifier? androidTtsAvailability,
  SettingsStore? settingsStore,
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
      androidTtsAvailability: androidTtsAvailability,
      settingsStore: settingsStore,
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
