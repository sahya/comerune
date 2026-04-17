import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/comment_post/comment_post_controller.dart';
import 'package:comerune/domain/models/comment_post_result.dart';
import 'package:comerune/presentation/errors/user_facing_error_messages.dart';

/// Regression-lock tests for [commentPostErrorMessage] (issue #521).
///
/// The mapping was previously a private instance method
/// (`_commentPostErrorMessage`) on `_CommentScreenState`, which made it
/// impossible to unit-test without spinning up the whole widget. It has been
/// extracted as a top-level `@visibleForTesting` function mirroring the
/// broadcast-side precedent [broadcastControlErrorMessage] (see
/// `broadcast_control_panel_test.dart`).
///
/// These tests pin every branch of the switch so a future edit cannot
/// silently collapse or reword a user-facing message.
void main() {
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
