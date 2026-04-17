// Shared user-facing error-message helpers.
//
// The comment-post UI ([commentPostErrorMessage]) and the broadcast-control
// UI ([broadcastControlErrorMessage]) both map backend error codes onto a
// snackbar string. Several branches produce semantically equivalent wording
// ("ログインが必要です" for auth failure, "ネットワークエラーが発生しました"
// for network failure, etc.) and must stay in sync so users see a
// consistent vocabulary across features.
//
// Previously these two helpers lived as top-level `@visibleForTesting`
// functions in their respective screen/widget files, which let the two
// copies drift — a reword in one place could silently diverge from the
// other. This module consolidates them so the shared wording is defined
// exactly once as a private library-level constant (`_k…Message`) and a
// future rename or translation edit lands in one place.
//
// The functions are plain top-level helpers (no `@visibleForTesting` —
// they are legitimate presentation-layer API now that they live in a
// dedicated module, and tests reach them through a normal import).
//
// Non-shared wording (e.g. branch-specific messages that only apply to one
// domain) is intentionally kept inline to avoid over-extracting constants
// that have no drift risk.

import '../../application/comment_post/comment_post_controller.dart';
import '../../domain/models/broadcast_control_result.dart';
import '../../domain/models/comment_post_result.dart';

// ---------------------------------------------------------------------------
// Shared wording constants
// ---------------------------------------------------------------------------
// These strings appear in BOTH [commentPostErrorMessage] and
// [broadcastControlErrorMessage]. Edit here to update both call sites at once.

const String _kLoginRequiredMessage = 'ログインが必要です';
const String _kMalformedInputMessage = '入力に使用できない文字が含まれています。ログインし直してお試しください';
const String _kNetworkErrorMessage = 'ネットワークエラーが発生しました';
const String _kProgramNotFoundMessage = '番組が見つかりません';

// ---------------------------------------------------------------------------
// Comment-post mapping
// ---------------------------------------------------------------------------

/// Maps a [CommentSendResult] failure to a user-facing snackbar message.
///
/// Symmetric with [broadcastControlErrorMessage] on the broadcast-side: both
/// helpers live together in this module so UI-to-message mappings stay in
/// sync and can be pinned by widget-free unit tests. Keep the wording here
/// in sync (where semantically equivalent) with the broadcast mapping to
/// avoid drift between the two code paths.
///
/// **Usage scope**: this mapping is intentionally coupled to the
/// [CommentSendResult] domain (e.g. [CommentPostErrorCode.malformedInput]
/// refers specifically to comment-post input validation). Do not reuse
/// this function for unrelated UI contexts — route those through their
/// own mapping or add a new top-level helper in this module.
String commentPostErrorMessage(CommentSendResult result) {
  final CommentValidationError? validation = result.validationError;
  if (validation != null) {
    switch (validation) {
      case CommentValidationError.empty:
        return 'コメントを入力してください';
      case CommentValidationError.invisibleOnly:
        return 'コメントに使用できない文字のみが含まれています';
      case CommentValidationError.tooLong:
        return '文字数が上限を超えています';
      case CommentValidationError.missingSession:
        return _kLoginRequiredMessage;
      case CommentValidationError.missingProgram:
        return '番組情報が取得できません';
      case CommentValidationError.inFlight:
        // Unreachable in the UI because the send button is disabled while
        // sending; included for switch exhaustiveness.
        return '送信中です';
    }
  }
  final CommentPostResult? post = result.postResult;
  if (post == null) {
    // Defensive fallback: `CommentSendResult` only exposes two constructors
    // (`.validation` sets `postResult=null`, `.posted` sets it non-null),
    // so this branch is unreachable as long as the validation guard above
    // consumed the `.validation` case. Kept as a safety net in case a new
    // constructor is added without updating this mapping.
    return 'コメントの送信に失敗しました';
  }
  switch (post.errorCode) {
    case CommentPostErrorCode.invalidParams:
    case CommentPostErrorCode.unauthorized:
      return _kLoginRequiredMessage;
    case CommentPostErrorCode.malformedInput:
      // Non-empty but structurally bad input: prompting re-login would
      // mislead the user (symmetric with the broadcast-side mapping).
      return _kMalformedInputMessage;
    case CommentPostErrorCode.forbidden:
      return 'コメントの投稿権限がありません';
    case CommentPostErrorCode.notFound:
      return _kProgramNotFoundMessage;
    case CommentPostErrorCode.conflict:
      return '放送は終了しています';
    case CommentPostErrorCode.rateLimited:
      return 'しばらく待ってから再送信してください';
    case CommentPostErrorCode.networkError:
      return _kNetworkErrorMessage;
    default:
      return 'コメントの送信に失敗しました';
  }
}

// ---------------------------------------------------------------------------
// Broadcast-control mapping
// ---------------------------------------------------------------------------

/// Maps a [BroadcastControlResult] error to a user-friendly message.
///
/// [operation] is a short Japanese verb substring ("開始" / "終了") spliced
/// into the FORBIDDEN and default messages so the snackbar names the action
/// that failed.
///
/// **Usage scope**: this mapping is intentionally coupled to the
/// [BroadcastControlResult] domain. Do not reuse this function for
/// unrelated UI contexts — route those through their own mapping or add
/// a new top-level helper in this module.
String broadcastControlErrorMessage(
  String operation,
  BroadcastControlResult result,
) {
  switch (result.errorCode) {
    case BroadcastControlErrorCode.invalidParams:
    case BroadcastControlErrorCode.unauthorized:
      return _kLoginRequiredMessage;
    case BroadcastControlErrorCode.malformedInput:
      // Non-empty but structurally bad input: prompting re-login would
      // mislead the user (their session may be fine). Surface a distinct
      // diagnostic that hints at the next step (re-login to refresh the
      // session token, which is by far the most common real-world cause).
      return _kMalformedInputMessage;
    case BroadcastControlErrorCode.forbidden:
      return '放送の$operation権限がありません';
    case BroadcastControlErrorCode.notFound:
      return _kProgramNotFoundMessage;
    case BroadcastControlErrorCode.networkError:
      return _kNetworkErrorMessage;
    default:
      return '放送の$operationに失敗しました';
  }
}
