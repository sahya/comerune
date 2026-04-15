import '../../data/comment/live_comment_repository.dart';
import '../../data/follow/follow_program.dart';
import '../../data/follow/my_program_repository.dart';

/// Maximum length of a normal (viewer) comment.
const int kNormalCommentMaxLength = 75;

/// Maximum length of an operator (broadcaster) comment.
///
/// niconico does not publish the authoritative server-side limit. The only
/// known data point is a comment in
/// https://github.com/amanorox/nicolivehelperxx `main.js` L940 stating
/// "主コメは 80 文字". We add a small (~20%) safety margin on top of that
/// note so broadcasters are not cut off inside the known-good range, while
/// still leaving the server free to reject genuinely over-length values
/// with a meaningful error. See the follow-up issue for empirical
/// verification of the true server-side ceiling.
const int kOperatorCommentMaxLength = 100;

/// Outcome of [CommentPostController.ensureBroadcasterStatus].
enum BroadcasterCheckOutcome {
  /// The user is the broadcaster of the currently viewed program.
  broadcaster,

  /// The user is not the broadcaster (regular viewer, or broadcasting a
  /// different program).
  viewer,

  /// The check could not be completed (e.g. session empty, network error).
  /// Treated as "not a broadcaster" by the UI.
  unknown,
}

/// Reason why a pre-send validation rejected a comment.
enum CommentValidationError {
  empty,
  tooLong,
  missingSession,
  missingProgram,

  /// A previous send is still in flight. Semantically "try again shortly";
  /// the UI typically suppresses the error snackbar for this case since the
  /// send button is already disabled while sending.
  inFlight,
}

/// Combined result of a comment post attempt.
class CommentSendResult {
  const CommentSendResult.validation(this.validationError) : postResult = null;
  const CommentSendResult.posted(CommentPostResult result)
    : validationError = null,
      postResult = result;

  final CommentValidationError? validationError;
  final CommentPostResult? postResult;

  bool get isSuccess => postResult?.success ?? false;
}

/// Coordinates broadcaster detection, text validation, and comment posting.
///
/// This controller deliberately holds only the minimum state required to
/// avoid redundant work while the comment screen is open:
/// - the cached broadcaster-status result (checked at most once per instance)
/// - an in-flight send guard to prevent double-submission
///
/// It does not own program id or user session; those must be supplied
/// per-call by the presentation layer (which already has them as inputs).
class CommentPostController {
  CommentPostController({
    required LiveCommentRepository liveCommentRepository,
    required MyProgramRepository myProgramRepository,
  }) : _liveCommentRepository = liveCommentRepository,
       _myProgramRepository = myProgramRepository;

  final LiveCommentRepository _liveCommentRepository;
  final MyProgramRepository _myProgramRepository;

  BroadcasterCheckOutcome? _cachedBroadcasterOutcome;
  String? _cachedBroadcasterLv;
  String? _cachedBroadcasterSession;
  bool _isSending = false;
  bool _disposed = false;

  /// Whether a post request is currently in-flight.
  bool get isSending => _isSending;

  /// Client-side max length for the given comment type.
  ///
  /// [maxLength] overrides the default when supplied, keeping this helper
  /// aligned with the widget-level `normalMaxLength` / `operatorMaxLength`
  /// injection. Callers that do not need to override can omit the param
  /// and inherit the shared constants.
  static int maxLengthFor({required bool asOperator, int? maxLength}) {
    assert(
      maxLength == null || maxLength > 0,
      'maxLength override must be positive; callers that do not want to '
      'override should pass null.',
    );
    if (maxLength != null) {
      return maxLength;
    }
    return asOperator ? kOperatorCommentMaxLength : kNormalCommentMaxLength;
  }

  /// Validates [text] for the chosen comment type.
  ///
  /// Returns `null` when valid. [maxLength] overrides the default ceiling
  /// — pass the same value the UI used for its counter to keep
  /// client-side validation and UI feedback in sync (SSOT guarantee).
  static CommentValidationError? validateText({
    required String text,
    required bool asOperator,
    int? maxLength,
  }) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return CommentValidationError.empty;
    }
    if (text.length >
        maxLengthFor(asOperator: asOperator, maxLength: maxLength)) {
      return CommentValidationError.tooLong;
    }
    return null;
  }

  /// Computes a vpos (1/100-second offset from [beginAt]).
  ///
  /// Returns `0` (with no error) when [beginAt] is null. A negative
  /// difference is clamped to 0 as well; the API rejects negative vpos.
  static int computeVpos({required DateTime? beginAt, DateTime? now}) {
    if (beginAt == null) {
      return 0;
    }
    final DateTime reference = now ?? DateTime.now();
    final int ms = reference.difference(beginAt).inMilliseconds;
    if (ms <= 0) {
      return 0;
    }
    return ms ~/ 10;
  }

  /// Determines whether the current user is the broadcaster of [lv].
  ///
  /// The result is cached for the lifetime of this controller per-lv. When
  /// [lv] changes, the cache is invalidated and re-checked.
  Future<BroadcasterCheckOutcome> ensureBroadcasterStatus({
    required String lv,
    required String userSession,
  }) async {
    if (_disposed) {
      return BroadcasterCheckOutcome.unknown;
    }
    if (lv.isEmpty) {
      return BroadcasterCheckOutcome.unknown;
    }
    if (userSession.trim().isEmpty) {
      // Not logged in — treat as viewer. Do not query the server.
      return BroadcasterCheckOutcome.viewer;
    }

    // Cache key is (lv, session) — when the logged-in identity changes the
    // broadcaster status must be re-evaluated against the new user.
    final BroadcasterCheckOutcome? cached = _cachedBroadcasterOutcome;
    if (cached != null &&
        _cachedBroadcasterLv == lv &&
        _cachedBroadcasterSession == userSession) {
      return cached;
    }

    try {
      final FollowProgram? ownProgram = await _myProgramRepository
          .fetchOwnProgram(userSession: userSession);
      final BroadcasterCheckOutcome outcome =
          ownProgram != null && ownProgram.programId == lv
          ? BroadcasterCheckOutcome.broadcaster
          : BroadcasterCheckOutcome.viewer;
      _cachedBroadcasterOutcome = outcome;
      _cachedBroadcasterLv = lv;
      _cachedBroadcasterSession = userSession;
      return outcome;
    } on Exception {
      // Fetch itself is defensive (returns null on failure), but guard anyway.
      return BroadcasterCheckOutcome.unknown;
    }
  }

  /// Sends a comment. Validates [text] client-side first; on success calls
  /// the appropriate repository method.
  ///
  /// [beginAt] is used to compute vpos for normal comments. It is ignored
  /// for operator comments.
  ///
  /// [maxLength] must mirror the value the UI enforced for its counter.
  /// **Do not pass the module constant directly** — always pipe in the
  /// widget's effective limit so the UI draft and the server-contract
  /// validator agree on the same ceiling. Passing `null` falls back to
  /// the module defaults, which is only correct when the UI likewise used
  /// the defaults (i.e. no widget-level override was specified).
  ///
  /// Guards against concurrent sends: if a send is already in progress, this
  /// call returns a validation error `empty` (the UI disables the button, so
  /// this is mostly defensive).
  /// [isAnonymous] requests a 184 (anonymous) post for normal comments. It
  /// is **ignored for operator comments** since the operator endpoint has
  /// no such flag and operator posts are rendered under the "運営" label
  /// regardless. Defaults to `false` so existing non-toggle call sites
  /// retain the pre-toggle behaviour (comment posted with the viewer's
  /// nickname / id).
  Future<CommentSendResult> postComment({
    required String lv,
    required String userSession,
    required String text,
    required bool asOperator,
    DateTime? beginAt,
    DateTime? now,
    int? maxLength,
    bool isAnonymous = false,
  }) async {
    if (_disposed) {
      return const CommentSendResult.validation(
        CommentValidationError.missingProgram,
      );
    }
    if (lv.isEmpty) {
      return const CommentSendResult.validation(
        CommentValidationError.missingProgram,
      );
    }
    if (userSession.trim().isEmpty) {
      return const CommentSendResult.validation(
        CommentValidationError.missingSession,
      );
    }

    // Route the caller-supplied [maxLength] through the validator so the
    // UI counter ceiling and the client-side server-contract check stay
    // identical — prevents a UX break where the UI accepts a longer draft
    // that server-side validation would then reject locally as tooLong.
    final CommentValidationError? validation = validateText(
      text: text,
      asOperator: asOperator,
      maxLength: maxLength,
    );
    if (validation != null) {
      return CommentSendResult.validation(validation);
    }

    if (_isSending) {
      // Already sending — surface a dedicated validation error so the caller
      // can silently ignore it instead of displaying a misleading message.
      return const CommentSendResult.validation(
        CommentValidationError.inFlight,
      );
    }

    _isSending = true;
    try {
      final CommentPostResult result;
      if (asOperator) {
        result = await _liveCommentRepository.postOperatorComment(
          programId: lv,
          userSession: userSession,
          text: text,
        );
      } else {
        final int vpos = computeVpos(beginAt: beginAt, now: now);
        result = await _liveCommentRepository.postNormalComment(
          programId: lv,
          userSession: userSession,
          text: text,
          vpos: vpos,
          isAnonymous: isAnonymous,
        );
      }
      return CommentSendResult.posted(result);
    } finally {
      _isSending = false;
    }
  }

  /// Releases cached state and marks this controller as no longer usable.
  ///
  /// Idempotent — subsequent `dispose()` calls are a no-op, which keeps
  /// hot-reload / test teardown safe. Also safe to call while a
  /// `postComment` is in flight: the in-flight future completes normally
  /// but subsequent calls return a `missingProgram` validation error
  /// instead of touching the (possibly disposed) repositories. This
  /// controller does not own the repositories it was constructed with, so
  /// they are not closed here; callers must dispose them explicitly.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cachedBroadcasterOutcome = null;
    _cachedBroadcasterLv = null;
    _cachedBroadcasterSession = null;
  }
}
