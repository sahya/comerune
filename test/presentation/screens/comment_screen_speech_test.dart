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
import '../../helpers/recording_settings_store.dart';

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

