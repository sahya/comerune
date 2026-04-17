import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/comment_post/comment_post_controller.dart';
import 'package:comerune/domain/models/broadcast_control_result.dart';
import 'package:comerune/domain/models/comment_post_result.dart';
import 'package:comerune/presentation/errors/user_facing_error_messages.dart';

/// Cross-helper parity tests.
///
/// These tests exist to catch the exact regression this module was created
/// to prevent: a future contributor edits a shared wording on one side
/// (e.g. the comment-post branch) and forgets to update the symmetric
/// broadcast-control branch, causing the user to see two different
/// Japanese strings for semantically-equivalent auth / network / not-found
/// errors.
///
/// The two functions have different signatures and their own per-function
/// unit tests (`comment_screen_error_message_test.dart`,
/// `broadcast_control_panel_test.dart`) which already pin each individual
/// wording. This file pins the *equality* between the two functions for
/// the wordings that were deliberately extracted into shared
/// `_k…Message` constants.
void main() {
  group('user_facing_error_messages cross-helper wording parity', () {
    test('INVALID_PARAMS / UNAUTHORIZED → same login-required wording', () {
      final String commentLoginForInvalidParams = commentPostErrorMessage(
        const CommentSendResult.posted(
          CommentPostResult(
            success: false,
            errorCode: CommentPostErrorCode.invalidParams,
          ),
        ),
      );
      final String broadcastLoginForInvalidParams = userFacingBroadcastError(
        '開始',
        const BroadcastControlResult(
          success: false,
          errorCode: BroadcastControlErrorCode.invalidParams,
        ),
      );
      expect(
        commentLoginForInvalidParams,
        broadcastLoginForInvalidParams,
        reason:
            'INVALID_PARAMS must route to the same login-required snackbar '
            'on both paths (shared _kLoginRequiredMessage)',
      );

      final String commentLoginForUnauthorized = commentPostErrorMessage(
        const CommentSendResult.posted(
          CommentPostResult(
            success: false,
            errorCode: CommentPostErrorCode.unauthorized,
          ),
        ),
      );
      final String broadcastLoginForUnauthorized = userFacingBroadcastError(
        '終了',
        const BroadcastControlResult(
          success: false,
          errorCode: BroadcastControlErrorCode.unauthorized,
        ),
      );
      expect(commentLoginForUnauthorized, broadcastLoginForUnauthorized);
      expect(commentLoginForUnauthorized, commentLoginForInvalidParams);
    });

    test('MALFORMED_INPUT → same malformed-input wording on both paths', () {
      final String comment = commentPostErrorMessage(
        const CommentSendResult.posted(
          CommentPostResult(
            success: false,
            errorCode: CommentPostErrorCode.malformedInput,
          ),
        ),
      );
      final String broadcast = userFacingBroadcastError(
        '開始',
        const BroadcastControlResult(
          success: false,
          errorCode: BroadcastControlErrorCode.malformedInput,
        ),
      );
      expect(
        comment,
        broadcast,
        reason:
            'MALFORMED_INPUT wording must stay synchronised across the two '
            'paths (shared _kMalformedInputMessage)',
      );
    });

    test('NETWORK_ERROR → same network-error wording on both paths', () {
      final String comment = commentPostErrorMessage(
        const CommentSendResult.posted(
          CommentPostResult(
            success: false,
            errorCode: CommentPostErrorCode.networkError,
          ),
        ),
      );
      final String broadcast = userFacingBroadcastError(
        '終了',
        const BroadcastControlResult(
          success: false,
          errorCode: BroadcastControlErrorCode.networkError,
        ),
      );
      expect(
        comment,
        broadcast,
        reason:
            'NETWORK_ERROR wording must stay synchronised across the two '
            'paths (shared _kNetworkErrorMessage)',
      );
    });

    test('NOT_FOUND → same program-not-found wording on both paths', () {
      final String comment = commentPostErrorMessage(
        const CommentSendResult.posted(
          CommentPostResult(
            success: false,
            errorCode: CommentPostErrorCode.notFound,
          ),
        ),
      );
      final String broadcast = userFacingBroadcastError(
        '開始',
        const BroadcastControlResult(
          success: false,
          errorCode: BroadcastControlErrorCode.notFound,
        ),
      );
      expect(
        comment,
        broadcast,
        reason:
            'NOT_FOUND wording must stay synchronised across the two paths '
            '(shared _kProgramNotFoundMessage)',
      );
    });
  });
}
