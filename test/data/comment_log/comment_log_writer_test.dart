import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/comment_log/comment_log_writer.dart';
import 'package:comerune/domain/models/app_message.dart';

void main() {
  group('FileCommentLogWriter', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('comment_log_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns null when messages are empty', () async {
      final FileCommentLogWriter writer =
          FileCommentLogWriter(directory: tempDir, tempDirectory: tempDir);

      final String? result = await writer.save(
        lv: 'lv123',
        messages: const <AppMessage>[],
      );

      expect(result, isNull);
    });

    test('saves chat messages to file', () async {
      final FileCommentLogWriter writer =
          FileCommentLogWriter(directory: tempDir, tempDirectory: tempDir);

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          userId: 'user1',
          content: 'こんにちは',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: '2',
          timestamp: DateTime(2026, 3, 28, 12, 0, 5),
          userId: 'user2',
          content: 'テストメッセージ',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(
        lv: 'lv123',
        messages: messages,
      );

      expect(path, isNotNull);
      final File file = File(path!);
      expect(file.existsSync(), isTrue);

      final String content = await file.readAsString();
      expect(content, contains('user1'));
      expect(content, contains('こんにちは'));
      expect(content, contains('user2'));
      expect(content, contains('テストメッセージ'));
    });

    test('excludes gift and nicoad messages', () async {
      final FileCommentLogWriter writer =
          FileCommentLogWriter(directory: tempDir, tempDirectory: tempDir);

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'チャット',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: '2',
          timestamp: DateTime(2026, 3, 28, 12, 0, 1),
          content: 'ギフト',
          type: AppMessageType.gift,
        ),
        AppMessage(
          id: '3',
          timestamp: DateTime(2026, 3, 28, 12, 0, 2),
          content: 'ニコニ広告',
          type: AppMessageType.nicoad,
        ),
      ];

      final String? path = await writer.save(
        lv: 'lv456',
        messages: messages,
      );

      expect(path, isNotNull);
      final String content = await File(path!).readAsString();
      expect(content, contains('チャット'));
      expect(content, isNot(contains('ギフト')));
      expect(content, isNot(contains('ニコニ広告')));
    });

    test('file name contains lv number', () async {
      final FileCommentLogWriter writer =
          FileCommentLogWriter(directory: tempDir, tempDirectory: tempDir);

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'test',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(
        lv: 'lv789',
        messages: messages,
      );

      expect(path, isNotNull);
      expect(path, contains('lv789'));
    });

    test('creates directory if it does not exist', () async {
      final Directory subDir = Directory('${tempDir.path}/nested/comment_logs');
      final FileCommentLogWriter writer =
          FileCommentLogWriter(directory: subDir, tempDirectory: tempDir);

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'test',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(
        lv: 'lv100',
        messages: messages,
      );

      expect(path, isNotNull);
      expect(subDir.existsSync(), isTrue);
    });

    test('writeToTempFile writes to temp directory', () async {
      final Directory shareDir = Directory('${tempDir.path}/share_temp');
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: tempDir,
        tempDirectory: shareDir,
      );

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'shared content',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.writeToTempFile(
        lv: 'lv300',
        messages: messages,
      );

      expect(path, isNotNull);
      expect(path, contains('share_temp'));
      expect(path, contains('lv300'));
      final String content = await File(path!).readAsString();
      expect(content, contains('shared content'));
    });

    test('escapes tabs and newlines in content', () async {
      final FileCommentLogWriter writer =
          FileCommentLogWriter(directory: tempDir, tempDirectory: tempDir);

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'line1\tand\ttabs\nand\nnewlines',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(
        lv: 'lv200',
        messages: messages,
      );

      final String content = await File(path!).readAsString();
      final List<String> lines =
          content.split('\n').where((String l) => l.isNotEmpty).toList();
      expect(lines.length, 1);
    });
  });
}
