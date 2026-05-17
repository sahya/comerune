import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/comment_post/comment_post_controller.dart';
import 'package:comerune/domain/models/comment_post_result.dart';
import 'package:comerune/presentation/errors/user_facing_error_messages.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';

/// Pure-logic regression tests for the helpers behind `CommentScreen`:
///
/// * `ContentFilterConfig` / `MessageTypeVisibilityConfig` — the in-memory
///   widget parameter shape produced by the `CommentFilterConfig` split
///   (issue #457). The split changes only the in-memory parameter shape,
///   not the persistence format (AppSettings SharedPreferences keys are
///   untouched). These tests pin down the defaults and field distribution
///   so a future change cannot silently drift either class away from the
///   pre-split behavior.
///
/// * `commentPostErrorMessage` — the user-facing error mapping previously
///   hidden as a private instance method on `_CommentScreenState`. It was
///   extracted as a top-level `@visibleForTesting` function (issue #521)
///   mirroring the broadcast-side precedent
///   `broadcastControlErrorMessage`. These tests pin every branch of the
///   switch so a future edit cannot silently collapse or reword a
///   user-facing message.
void main() {
  group(
    'ContentFilterConfig defaults (backward compatibility with pre-split)',
    () {
      test(
        'matches pre-split CommentFilterConfig defaults bit-identically',
        () {
          const ContentFilterConfig filter = ContentFilterConfig();

          expect(filter.ngUserIds, isEmpty);
          expect(filter.ngWords, isEmpty);
          expect(filter.presetNgWords, isEmpty);
          expect(filter.starPrefixHidingEnabled, isFalse);
          expect(filter.slashPrefixSkipEnabled, isTrue);
          expect(filter.emphasizeGiftNicoadComment, isTrue);
          expect(filter.userColorMap, isEmpty);
          expect(filter.userNicknameMap, isEmpty);
          expect(filter.ngProtectionNotificationEnabled, isFalse);
        },
      );

      test('non-default values are preserved', () {
        const ContentFilterConfig filter = ContentFilterConfig(
          ngUserIds: <String>{'u1', 'u2'},
          ngWords: <String>['spam'],
          presetNgWords: <String>['preset'],
          starPrefixHidingEnabled: true,
          slashPrefixSkipEnabled: false,
          emphasizeGiftNicoadComment: false,
          userColorMap: <String, int>{'u1': 0xFF0000FF},
          userNicknameMap: <String, String>{'u1': 'nick'},
          ngProtectionNotificationEnabled: true,
        );

        expect(filter.ngUserIds, <String>{'u1', 'u2'});
        expect(filter.ngWords, <String>['spam']);
        expect(filter.presetNgWords, <String>['preset']);
        expect(filter.starPrefixHidingEnabled, isTrue);
        expect(filter.slashPrefixSkipEnabled, isFalse);
        expect(filter.emphasizeGiftNicoadComment, isFalse);
        expect(filter.userColorMap, <String, int>{'u1': 0xFF0000FF});
        expect(filter.userNicknameMap, <String, String>{'u1': 'nick'});
        expect(filter.ngProtectionNotificationEnabled, isTrue);
      });
    },
  );

  group(
    'MessageTypeVisibilityConfig defaults (backward compatibility with pre-split)',
    () {
      test(
        'matches pre-split CommentFilterConfig defaults bit-identically',
        () {
          const MessageTypeVisibilityConfig vis = MessageTypeVisibilityConfig();

          expect(vis.showOperatorComment, isTrue);
          expect(vis.showSystemMessage, isTrue);
          expect(vis.showEmotion, isTrue);
          expect(vis.showGiftComment, isTrue);
          expect(vis.showNicoadComment, isTrue);
        },
      );

      test('non-default values are preserved', () {
        const MessageTypeVisibilityConfig vis = MessageTypeVisibilityConfig(
          showOperatorComment: false,
          showSystemMessage: false,
          showEmotion: false,
          showGiftComment: false,
          showNicoadComment: false,
        );

        expect(vis.showOperatorComment, isFalse);
        expect(vis.showSystemMessage, isFalse);
        expect(vis.showEmotion, isFalse);
        expect(vis.showGiftComment, isFalse);
        expect(vis.showNicoadComment, isFalse);
      });
    },
  );

  group('Field distribution across the split', () {
    test('ContentFilterConfig carries content/user-based filter fields', () {
      // Compile-time cross-check: these accessors must exist on
      // ContentFilterConfig. If any is moved, this test fails to compile.
      const ContentFilterConfig filter = ContentFilterConfig();
      // ignore: unnecessary_statements
      filter.ngUserIds;
      // ignore: unnecessary_statements
      filter.ngWords;
      // ignore: unnecessary_statements
      filter.presetNgWords;
      // ignore: unnecessary_statements
      filter.starPrefixHidingEnabled;
      // ignore: unnecessary_statements
      filter.slashPrefixSkipEnabled;
      // ignore: unnecessary_statements
      filter.emphasizeGiftNicoadComment;
      // ignore: unnecessary_statements
      filter.userColorMap;
      // ignore: unnecessary_statements
      filter.userNicknameMap;
      // ignore: unnecessary_statements
      filter.ngProtectionNotificationEnabled;
    });

    test(
      'MessageTypeVisibilityConfig carries message-type display toggles',
      () {
        const MessageTypeVisibilityConfig vis = MessageTypeVisibilityConfig();
        // ignore: unnecessary_statements
        vis.showOperatorComment;
        // ignore: unnecessary_statements
        vis.showSystemMessage;
        // ignore: unnecessary_statements
        vis.showEmotion;
        // ignore: unnecessary_statements
        vis.showGiftComment;
        // ignore: unnecessary_statements
        vis.showNicoadComment;
      },
    );
  });

  group('commentPostErrorMessage - validation branches', () {
    test('empty -> prompt to enter comment', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.validation(CommentValidationError.empty),
        ),
        'コメントを入力してください',
      );
    });

    test('invisibleOnly -> invisible-only characters message', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.validation(
            CommentValidationError.invisibleOnly,
          ),
        ),
        'コメントに使用できない文字のみが含まれています',
      );
    });

    test('tooLong -> length limit message', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.validation(CommentValidationError.tooLong),
        ),
        '文字数が上限を超えています',
      );
    });

    test('missingSession -> login required', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.validation(
            CommentValidationError.missingSession,
          ),
        ),
        'ログインが必要です',
      );
    });

    test('missingProgram -> program info unavailable', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.validation(
            CommentValidationError.missingProgram,
          ),
        ),
        '番組情報が取得できません',
      );
    });

    test('inFlight -> in-flight message (exhaustiveness branch)', () {
      // This branch is unreachable from the UI in practice (the send button
      // is disabled while a previous send is in flight) but the function
      // must still return a deterministic message so a future refactor that
      // removes the disable-guard does not fall through to a misleading
      // generic failure.
      expect(
        commentPostErrorMessage(
          const CommentSendResult.validation(CommentValidationError.inFlight),
        ),
        '送信中です',
      );
    });
  });

  group('commentPostErrorMessage - post.errorCode branches', () {
    test('INVALID_PARAMS -> login required', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(
              success: false,
              errorCode: CommentPostErrorCode.invalidParams,
            ),
          ),
        ),
        'ログインが必要です',
      );
    });

    test('MALFORMED_INPUT -> malformed-input message '
        '(not misleading sign-in prompt)', () {
      // Regression lock mirroring the broadcast-side test in
      // broadcast_control_panel_test.dart:352-372 (Issue #518 MUST FIX).
      // MALFORMED_INPUT must NOT collapse into the same sign-in prompt as
      // INVALID_PARAMS / UNAUTHORIZED. Surfacing "please sign in" for a
      // non-empty but structurally bad input misleads the user into an
      // unhelpful re-login loop.
      final String message = commentPostErrorMessage(
        const CommentSendResult.posted(
          CommentPostResult(
            success: false,
            errorCode: CommentPostErrorCode.malformedInput,
          ),
        ),
      );
      expect(message, '入力に使用できない文字が含まれています。ログインし直してお試しください');
      expect(
        message,
        isNot('ログインが必要です'),
        reason: 'MALFORMED_INPUT must not collapse into sign-in prompt',
      );
    });

    test('UNAUTHORIZED -> login required', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(
              success: false,
              errorCode: CommentPostErrorCode.unauthorized,
            ),
          ),
        ),
        'ログインが必要です',
      );
    });

    test('FORBIDDEN -> no permission to post comments', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(
              success: false,
              errorCode: CommentPostErrorCode.forbidden,
            ),
          ),
        ),
        'コメントの投稿権限がありません',
      );
    });

    test('NOT_FOUND -> program not found', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(
              success: false,
              errorCode: CommentPostErrorCode.notFound,
            ),
          ),
        ),
        '番組が見つかりません',
      );
    });

    test('CONFLICT -> broadcast ended', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(
              success: false,
              errorCode: CommentPostErrorCode.conflict,
            ),
          ),
        ),
        '放送は終了しています',
      );
    });

    test('RATE_LIMITED -> retry later', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(
              success: false,
              errorCode: CommentPostErrorCode.rateLimited,
            ),
          ),
        ),
        'しばらく待ってから再送信してください',
      );
    });

    test('NETWORK_ERROR -> network error', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(
              success: false,
              errorCode: CommentPostErrorCode.networkError,
            ),
          ),
        ),
        'ネットワークエラーが発生しました',
      );
    });

    test('unknown errorCode (e.g. HTTP_500) -> generic failure', () {
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(
            CommentPostResult(success: false, errorCode: 'HTTP_500'),
          ),
        ),
        'コメントの送信に失敗しました',
      );
    });

    test('null errorCode (post-result without code) -> generic failure', () {
      // `CommentSendResult.posted` wraps a CommentPostResult whose errorCode
      // may be null (e.g. server returned failure but no code). The switch
      // must fall through to the default branch rather than throwing.
      expect(
        commentPostErrorMessage(
          const CommentSendResult.posted(CommentPostResult(success: false)),
        ),
        'コメントの送信に失敗しました',
      );
    });
  });
}
