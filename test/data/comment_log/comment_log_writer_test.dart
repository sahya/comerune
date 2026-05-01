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
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: tempDir,
        tempDirectory: tempDir,
      );

      final String? result = await writer.save(
        lv: 'lv123',
        messages: const <AppMessage>[],
      );

      expect(result, isNull);
    });

    test('saves chat messages to file', () async {
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: tempDir,
        tempDirectory: tempDir,
      );

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

      final String? path = await writer.save(lv: 'lv123', messages: messages);

      expect(path, isNotNull);
      final File file = File(path!);
      expect(file.existsSync(), isTrue);

      final String content = await file.readAsString();
      expect(content, contains('user1'));
      expect(content, contains('こんにちは'));
      expect(content, contains('user2'));
      expect(content, contains('テストメッセージ'));
    });

    test(
      'writes all passed messages (caller responsible for filtering)',
      () async {
        final FileCommentLogWriter writer = FileCommentLogWriter(
          directory: tempDir,
          tempDirectory: tempDir,
        );

        // Only chat messages are passed (caller filters out gift/nicoad).
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: '1',
            timestamp: DateTime(2026, 3, 28, 12, 0, 0),
            content: 'チャット',
            type: AppMessageType.chat,
          ),
        ];

        final String? path = await writer.save(lv: 'lv456', messages: messages);

        expect(path, isNotNull);
        final String content = await File(path!).readAsString();
        expect(content, contains('チャット'));
      },
    );

    test('file name contains lv number', () async {
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: tempDir,
        tempDirectory: tempDir,
      );

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'test',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(lv: 'lv789', messages: messages);

      expect(path, isNotNull);
      expect(path, contains('lv789'));
    });

    test('creates directory if it does not exist', () async {
      final Directory subDir = Directory('${tempDir.path}/nested/comment_logs');
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: subDir,
        tempDirectory: tempDir,
      );

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'test',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(lv: 'lv100', messages: messages);

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

    test('save uses customDirectory when provided', () async {
      final Directory customDir = Directory('${tempDir.path}/custom_save_dir');
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: tempDir,
        tempDirectory: tempDir,
      );

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'custom dir test',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(
        lv: 'lv500',
        messages: messages,
        customDirectory: customDir,
      );

      expect(path, isNotNull);
      expect(path, contains('custom_save_dir'));
      expect(customDir.existsSync(), isTrue);
      final String content = await File(path!).readAsString();
      expect(content, contains('custom dir test'));
    });

    test('save uses default directory when customDirectory is null', () async {
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: tempDir,
        tempDirectory: tempDir,
      );

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'default dir test',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(lv: 'lv600', messages: messages);

      expect(path, isNotNull);
      expect(path, startsWith(tempDir.path));
    });

    test('escapes tabs and newlines in content', () async {
      final FileCommentLogWriter writer = FileCommentLogWriter(
        directory: tempDir,
        tempDirectory: tempDir,
      );

      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '1',
          timestamp: DateTime(2026, 3, 28, 12, 0, 0),
          content: 'line1\tand\ttabs\nand\nnewlines',
          type: AppMessageType.chat,
        ),
      ];

      final String? path = await writer.save(lv: 'lv200', messages: messages);

      final String content = await File(path!).readAsString();
      final List<String> lines = content
          .split('\n')
          .where((String l) => l.isNotEmpty)
          .toList();
      expect(lines.length, 1);
    });

    // Issue #784, Phase 2 / PR-2.
    // Comment log file format expanded from 3 columns to 4 with the
    // commentNo column prepended. The new column is `''` (empty string)
    // for messages that do not carry a number, and the column count
    // stays fixed at 4 even when no message in the file has a number.
    group('commentNo column (Issue #784, PR-2)', () {
      // T16: chat messages with non-null commentNo get the value in col 1.
      test(
        'writes 4 columns with commentNo when message carries a number',
        () async {
          final FileCommentLogWriter writer = FileCommentLogWriter(
            directory: tempDir,
            tempDirectory: tempDir,
          );

          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: '1',
              timestamp: DateTime(2026, 5, 1, 12, 34, 56),
              userId: 'user1',
              content: 'hello',
              type: AppMessageType.chat,
              commentNo: 123,
            ),
          ];

          final String? path = await writer.save(
            lv: 'lv784a',
            messages: messages,
          );
          final String content = await File(path!).readAsString();
          final String line = content.split('\n').first;
          expect(line, '123\t12:34:56\tuser1\thello');
          expect(line.split('\t').length, 4);
        },
      );

      // T17: chat messages without a number still produce 4 columns,
      // with col 1 left as the empty string.
      test('writes 4 columns with empty commentNo column when null', () async {
        final FileCommentLogWriter writer = FileCommentLogWriter(
          directory: tempDir,
          tempDirectory: tempDir,
        );

        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: '1',
            timestamp: DateTime(2026, 5, 1, 12, 34, 56),
            userId: 'user1',
            content: 'no number',
            type: AppMessageType.chat,
          ),
        ];

        final String? path = await writer.save(
          lv: 'lv784b',
          messages: messages,
        );
        final String content = await File(path!).readAsString();
        final String line = content.split('\n').first;
        // Empty commentNo still occupies col 1, so the line begins with TAB.
        expect(line.startsWith('\t'), isTrue);
        expect(line, '\t12:34:56\tuser1\tno number');
        expect(line.split('\t').length, 4);
      });

      // T18: mixed file (one with number, one without) keeps the column
      // count uniform so external TSV parsers can rely on it.
      test('mixed messages keep column count fixed at 4', () async {
        final FileCommentLogWriter writer = FileCommentLogWriter(
          directory: tempDir,
          tempDirectory: tempDir,
        );

        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: '1',
            timestamp: DateTime(2026, 5, 1, 12, 0, 0),
            userId: 'user1',
            content: 'with number',
            type: AppMessageType.chat,
            commentNo: 100,
          ),
          AppMessage(
            id: '2',
            timestamp: DateTime(2026, 5, 1, 12, 0, 1),
            userId: 'user2',
            content: 'no number',
            type: AppMessageType.chat,
          ),
          AppMessage(
            id: '3',
            timestamp: DateTime(2026, 5, 1, 12, 0, 2),
            userId: null,
            content: '運営からのお知らせ',
            type: AppMessageType.operator,
          ),
        ];

        final String? path = await writer.save(
          lv: 'lv784c',
          messages: messages,
        );
        final String content = await File(path!).readAsString();
        final List<String> lines = content
            .split('\n')
            .where((String l) => l.isNotEmpty)
            .toList();
        expect(lines.length, 3);
        for (final String line in lines) {
          expect(
            line.split('\t').length,
            4,
            reason: 'Every row must keep the 4-column shape: $line',
          );
        }
        expect(lines[0], '100\t12:00:00\tuser1\twith number');
        expect(lines[1], '\t12:00:01\tuser2\tno number');
        expect(lines[2], '\t12:00:02\t\t運営からのお知らせ');
      });

      // 賢者2 (テスト仙人) SHOULD FIX: docstring の宣言 (commentNo が
      // null になる経路) を AppMessageType ごとに明示的に裏付ける。実装
      // 自体は AppMessage.commentNo を見るだけで type 別分岐は無いが、
      // 「将来 type 別分岐が混入したら検知できる」というレギュレーションを
      // テストとして据える。
      // Note: chat メッセージで `commentNo: 0` / `-1` のような不正値は
      // PR-1 (#787) の `_sanitizeCommentNo` が `null` 化するので、この
      // ファイル単独では「null か正の値」しか writer に届かない前提。
      test(
        'AppMessageType.system / gift / nicoad / operator emit empty commentNo column',
        () async {
          final FileCommentLogWriter writer = FileCommentLogWriter(
            directory: tempDir,
            tempDirectory: tempDir,
          );

          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: 'sys',
              timestamp: DateTime(2026, 5, 1, 12, 0, 0),
              userId: null,
              content: '市場 sys',
              type: AppMessageType.system,
            ),
            AppMessage(
              id: 'em',
              timestamp: DateTime(2026, 5, 1, 12, 0, 1),
              userId: null,
              content: 'emotion ev',
              type: AppMessageType.emotion,
            ),
            AppMessage(
              id: 'noti',
              timestamp: DateTime(2026, 5, 1, 12, 0, 2),
              userId: null,
              content: '通知',
              type: AppMessageType.notification,
            ),
            AppMessage(
              id: 'gift',
              timestamp: DateTime(2026, 5, 1, 12, 0, 3),
              userId: null,
              content: 'gift presented',
              type: AppMessageType.gift,
            ),
            AppMessage(
              id: 'ad',
              timestamp: DateTime(2026, 5, 1, 12, 0, 4),
              userId: null,
              content: 'nicoad msg',
              type: AppMessageType.nicoad,
            ),
            AppMessage(
              id: 'op',
              timestamp: DateTime(2026, 5, 1, 12, 0, 5),
              userId: null,
              content: '運営お知らせ',
              type: AppMessageType.operator,
            ),
          ];

          final String? path = await writer.save(
            lv: 'lv784e',
            messages: messages,
          );
          final String content = await File(path!).readAsString();
          final List<String> lines = content
              .split('\n')
              .where((String l) => l.isNotEmpty)
              .toList();
          expect(lines.length, messages.length);
          for (final String line in lines) {
            final List<String> cols = line.split('\t');
            expect(cols.length, 4, reason: 'every type emits 4 columns: $line');
            expect(
              cols.first,
              isEmpty,
              reason:
                  'commentNo column must be empty for non-chat types: $line',
            );
          }
        },
      );

      // Defence-in-depth: tab/newline injection in commentNo is impossible
      // because the field is `int?`, but pin the row shape explicitly so a
      // future change (say, switching to `String?`) cannot bypass escaping
      // without also breaking this test.
      test(
        'commentNo column does not contain tab or newline characters',
        () async {
          final FileCommentLogWriter writer = FileCommentLogWriter(
            directory: tempDir,
            tempDirectory: tempDir,
          );

          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: '1',
              timestamp: DateTime(2026, 5, 1, 12, 34, 56),
              userId: 'user1',
              content: 'safe',
              type: AppMessageType.chat,
              commentNo: 0x7FFFFFFF, // max int32
            ),
          ];

          final String? path = await writer.save(
            lv: 'lv784d',
            messages: messages,
          );
          final String content = await File(path!).readAsString();
          final String line = content.split('\n').first;
          final String commentNoColumn = line.split('\t').first;
          expect(commentNoColumn.contains('\t'), isFalse);
          expect(commentNoColumn.contains('\n'), isFalse);
          expect(commentNoColumn, '2147483647');
        },
      );
    });
  });
}
