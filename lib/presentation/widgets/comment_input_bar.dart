import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_logging.dart';
import '../../application/comment_post/comment_post_controller.dart';

/// Send callback signature for [CommentInputBar].
///
/// Returns the result of the post attempt so the caller can show
/// an error snackbar when it fails.
typedef CommentSendCallback =
    Future<CommentSendResult> Function({
      required String text,
      required bool asOperator,

      /// The effective max length the UI enforced when the user pressed
      /// send. Passed through to the controller's validator so client-side
      /// checks stay in sync with the UI counter (SSOT).
      required int maxLength,

      /// When `true`, the viewer asked to post as 184 (anonymous: no
      /// nickname / id shown to other clients). Ignored for operator
      /// comments (operator posts are always labelled "運営" server-side).
      required bool isAnonymous,
    });

/// Semi-transparent floating action button that opens the comment-post
/// input overlay when tapped.
///
/// Rendered as an overlay inside a [Stack] — the parent is responsible for
/// positioning (typically right-bottom, above any other overlays).
class CommentPostFab extends StatelessWidget {
  const CommentPostFab({super.key, required this.onPressed});

  /// Invoked when the user taps the FAB to expand the input overlay.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Hand-rolled FAB: Flutter's built-in FloatingActionButton does not
    // expose `surfaceTintColor`, so Material-3's elevation-based tint is
    // always blended into `backgroundColor`, which silently fills in the
    // alpha we set. Using a Material widget directly lets us force
    // `surfaceTintColor: Colors.transparent` and keep the alpha visible.
    //
    // TODO(upstream): when a future Flutter version exposes
    // `FloatingActionButton.surfaceTintColor`, revert this hand-rolled
    // version back to `FloatingActionButton.small` and pass
    // `surfaceTintColor: Colors.transparent` to it directly.
    const double visualSize = 40;
    const double tapTargetSize = 48;
    return Semantics(
      button: true,
      container: true,
      label: 'コメントを投稿',
      child: Tooltip(
        message: 'コメントを投稿',
        child: SizedBox(
          width: tapTargetSize,
          height: tapTargetSize,
          child: Center(
            child: SizedBox(
              width: visualSize,
              height: visualSize,
              child: Material(
                // Alpha 0.55 keeps underlying comments legible through
                // the FAB (Issue #123 spec: "高めの透過度").
                color: theme.colorScheme.primary.withValues(alpha: 0.55),
                surfaceTintColor: Colors.transparent,
                shape: const CircleBorder(),
                elevation: 6,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('comment-post-fab'),
                  onTap: onPressed,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(
                      Icons.edit_outlined,
                      size: 22,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Expanded comment input bar: text field, optional broadcaster-only
/// operator/normal toggle, and send + close buttons.
///
/// The parent owns the expanded/collapsed state and only mounts this widget
/// while in the expanded state. When a send succeeds this widget calls
/// [onCollapse] so the parent can dismiss it.
class CommentInputBar extends StatefulWidget {
  const CommentInputBar({
    super.key,
    required this.isBroadcaster,
    required this.onSend,
    required this.onCollapse,
    this.onSendingChanged,
    this.normalMaxLength = kNormalCommentMaxLength,
    this.operatorMaxLength = kOperatorCommentMaxLength,
  }) : assert(normalMaxLength > 0, 'normalMaxLength must be positive'),
       assert(operatorMaxLength > 0, 'operatorMaxLength must be positive');

  /// Whether the user is the broadcaster of the currently viewed program.
  /// Controls visibility of the operator/normal toggle.
  final bool isBroadcaster;

  /// Invoked when the user taps the send button with a valid draft.
  final CommentSendCallback onSend;

  /// Invoked when the input bar should be dismissed (send success or the
  /// user tapped close).
  final VoidCallback onCollapse;

  /// Notifies the parent when a send starts or completes. Useful so the
  /// parent can e.g. ignore outside-taps while a request is in flight and
  /// avoid dismissing the bar out from under an in-progress submission.
  final ValueChanged<bool>? onSendingChanged;

  /// Maximum length of a normal (viewer) comment the UI accepts.
  ///
  /// Defaults to [kNormalCommentMaxLength]. Exposed as a parameter so that
  /// callers can override it when niconico's server-side ceiling changes
  /// (tracked by the follow-up investigation issue) without rewriting the
  /// widget, and so that tests can pin a deterministic boundary value.
  final int normalMaxLength;

  /// Maximum length of an operator (broadcaster) comment the UI accepts.
  ///
  /// Defaults to [kOperatorCommentMaxLength] (currently 100, derived from
  /// nicolivehelperxx's in-code note "主コメは 80 文字" with a ~20% safety
  /// margin). Override when the real ceiling is measured empirically.
  final int operatorMaxLength;

  @override
  State<CommentInputBar> createState() => _CommentInputBarState();
}

class _CommentInputBarState extends State<CommentInputBar> {
  final TextEditingController _textController = TextEditingController();
  late final FocusNode _focusNode;
  bool _sending = false;

  /// Current selection: when user is broadcaster, defaults to operator (per
  /// issue spec). Kept on state so the selection survives draft editing.
  bool _asOperator = true;

  /// Whether the viewer asked to post as 184 (anonymous). Defaults to
  /// `false` (=名札付き) per Issue #463. Reset back to `false` whenever
  /// the bar switches into operator mode so a stale anonymous selection
  /// cannot leak into a subsequent normal-mode post — operator mode has
  /// no anonymous concept, and Issue #463 prefers a simple reset policy
  /// over restoring the previous value.
  bool _isAnonymous = false;

  @override
  void initState() {
    super.initState();
    // Hardware-keyboard Enter submits; Shift+Enter falls through to the
    // TextField to insert a newline. The mobile soft-keyboard "send" button
    // is handled separately by the TextField's onSubmitted callback.
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    // Broadcaster status can change from the parent; start in a mode that
    // matches the current flag.
    _asOperator = widget.isBroadcaster;
    // Focus immediately after first frame so the keyboard opens as soon as
    // the bar appears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Key shortcut contract (pinned by widget tests):
    //   - Enter / NumpadEnter   → submit (if the draft is valid)
    //   - Shift+Enter           → newline (fall through to TextField)
    //   - Ctrl / Alt / Meta + Enter → submit (treated identically to plain
    //     Enter so chat-app muscle memory "Ctrl+Enter to send" still works)
    //
    // Fires only for hardware-keyboard events. Key events consumed by an
    // active IME (e.g. Japanese 変換確定 Enter) are delivered to the IME
    // first and do not reach this handler, so Enter-to-confirm during IME
    // composition is not hijacked as a submit.
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Shift+Enter = newline (let the TextField handle it).
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (!_canSendForValue(_textController.value)) {
      // Swallow plain-Enter even when the draft is invalid (or a previous
      // send is still in-flight) so the user does not accidentally add a
      // newline when trying to submit, and so that re-pressing Enter while
      // _sending=true cannot trigger a second request.
      return KeyEventResult.handled;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant CommentInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isBroadcaster && _asOperator) {
      // Broadcaster status was lost (e.g. ended broadcast) — reset toggle
      // so a stale operator-mode selection does not leak into viewer mode.
      _asOperator = false;
    } else if (widget.isBroadcaster && !oldWidget.isBroadcaster) {
      // Broadcaster status arrived after the bar was already mounted: this
      // happens in production when the parent's async broadcaster check
      // (`_resolveCommentPostContext`) lands a frame or two after the
      // overlay opens. Per the Issue #123 spec the broadcaster default is
      // operator mode, so flip the toggle on the transition.
      _asOperator = true;
      // The anonymous toggle has no meaning in operator mode — reset it
      // so the next normal-mode flip starts from the "名札付き" default.
      _isAnonymous = false;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int get _maxLength {
    final bool asOperator = widget.isBroadcaster && _asOperator;
    // Prefer the caller-injected max length so a single niconico spec update
    // can be applied at the widget construction site without touching the
    // shared constants used by server-side validation.
    return asOperator ? widget.operatorMaxLength : widget.normalMaxLength;
  }

  bool _canSendForValue(TextEditingValue value) {
    if (_sending) {
      return false;
    }
    if (value.text.trim().isEmpty) {
      return false;
    }
    if (value.text.length > _maxLength) {
      return false;
    }
    return true;
  }

  Future<void> _send() async {
    final TextEditingValue value = _textController.value;
    if (!_canSendForValue(value)) {
      appDebugLogLazy(
        () =>
            '[CommentInputBar] _send: canSend=false '
            'sending=$_sending text="${value.text}" '
            'length=${value.text.length} maxLength=$_maxLength',
      );
      return;
    }
    final String text = value.text;
    final bool asOperator = widget.isBroadcaster && _asOperator;
    final bool isAnonymous = !asOperator && _isAnonymous;

    appDebugLogLazy(
      () =>
          '[CommentInputBar] _send START: '
          'text="${text.length > 20 ? '${text.substring(0, 20)}...' : text}" '
          '(${text.length} chars) asOperator=$asOperator '
          'isAnonymous=$isAnonymous maxLength=$_maxLength '
          'isBroadcaster=${widget.isBroadcaster} '
          '_asOperator=$_asOperator _isAnonymous=$_isAnonymous',
    );

    setState(() {
      _sending = true;
    });
    widget.onSendingChanged?.call(true);
    try {
      final CommentSendResult result = await widget.onSend(
        text: text,
        asOperator: asOperator,
        maxLength: _maxLength,
        isAnonymous: isAnonymous,
      );
      appDebugLogLazy(
        () =>
            '[CommentInputBar] _send result: '
            'isSuccess=${result.isSuccess} '
            'validationError=${result.validationError} '
            'postResult.errorCode=${result.postResult?.errorCode}',
      );
      if (!mounted) {
        widget.onSendingChanged?.call(false);
        return;
      }
      if (result.isSuccess) {
        widget.onSendingChanged?.call(false);
        widget.onCollapse();
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
        widget.onSendingChanged?.call(false);
      }
    }
  }

  void _handleClose() {
    if (_sending) {
      return;
    }
    _focusNode.unfocus();
    widget.onCollapse();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  if (widget.isBroadcaster) ...<Widget>[
                    _OperatorToggle(
                      asOperator: _asOperator,
                      onChanged: (bool value) {
                        setState(() {
                          _asOperator = value;
                          if (value) {
                            // Switching to operator mode drops the
                            // anonymous selection — the operator endpoint
                            // has no such flag and a stale `true` would
                            // silently revive on the next normal-mode
                            // flip, surprising the user.
                            _isAnonymous = false;
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                  // The 184 toggle is visible for viewers and for
                  // broadcasters while the mode toggle is on "通常".
                  // Operator mode hides it because the endpoint has no
                  // `isAnonymous` field and operator posts are labelled
                  // "運営" by the server.
                  if (!(widget.isBroadcaster && _asOperator))
                    _AnonymousToggle(
                      isAnonymous: _isAnonymous,
                      onChanged: (bool value) {
                        setState(() {
                          _isAnonymous = value;
                        });
                      },
                    ),
                  Expanded(
                    child: TextField(
                      key: const Key('comment-post-textfield'),
                      controller: _textController,
                      focusNode: _focusNode,
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: widget.isBroadcaster && _asOperator
                            ? '運営コメントを入力${kDebugMode ? '（デバッグ）' : ''}'
                            : 'コメントを入力${kDebugMode ? '（デバッグ）' : ''}',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('comment-post-close-button'),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: '閉じる',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: _sending ? null : _handleClose,
                  ),
                  // Send button and counter react only to text changes without
                  // rebuilding the TextField / toggle / close-button.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _textController,
                    builder:
                        (
                          BuildContext context,
                          TextEditingValue value,
                          Widget? _,
                        ) {
                          return IconButton(
                            key: const Key('comment-post-send-button'),
                            icon: _sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send, size: 20),
                            tooltip: '送信 (Enter / Shift+Enter で改行)',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            onPressed: _canSendForValue(value) ? _send : null,
                          );
                        },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder:
                      (
                        BuildContext context,
                        TextEditingValue value,
                        Widget? _,
                      ) {
                        final int currentLength = value.text.length;
                        final int maxLength = _maxLength;
                        final bool overLimit = currentLength > maxLength;
                        return Text(
                          '$currentLength / $maxLength',
                          key: const Key('comment-post-counter'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: overLimit
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: overLimit
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        );
                      },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon-only two-state toggle that switches between 名札付き (nickname
/// shown) and 名札なし (184 anonymous). The text label was removed to make
/// room for the input field; the mode is conveyed by the icon + its
/// active/inactive color and by the tooltip/semantics for accessibility.
class _AnonymousToggle extends StatelessWidget {
  const _AnonymousToggle({required this.isAnonymous, required this.onChanged});

  final bool isAnonymous;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      toggled: isAnonymous,
      label: isAnonymous ? '名札なしモード（選択中）' : '名札付きモード（選択中）',
      hint: 'タップで名札付きと名札なしを切り替え',
      child: Tooltip(
        message: isAnonymous ? '名札なし（タップで名札付きに）' : '名札付き（タップで名札なしに）',
        child: InkWell(
          key: const Key('comment-post-anonymous-toggle'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(!isAnonymous),
          child: Padding(
            // 8+20+8 = 36pt: matches the compact-density send/close buttons
            // and stays within the Material minimum tap target guidance.
            padding: const EdgeInsets.all(8),
            child: Icon(
              isAnonymous ? Icons.person_off : Icons.person,
              size: 20,
              color: isAnonymous
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _OperatorToggle extends StatelessWidget {
  const _OperatorToggle({required this.asOperator, required this.onChanged});

  final bool asOperator;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Expose this as an a11y toggle button with the currently-selected
    // mode so screen readers announce e.g. "運営コメントモード, toggle, selected"
    // and the user can change it with an explicit action gesture.
    return Semantics(
      button: true,
      toggled: asOperator,
      label: asOperator ? '運営コメントモード（選択中）' : '通常コメントモード（選択中）',
      hint: 'タップで運営と通常を切り替え',
      child: InkWell(
        key: const Key('comment-post-operator-toggle'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!asOperator),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                asOperator ? Icons.campaign : Icons.chat_bubble_outline,
                size: 18,
                color: asOperator
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                asOperator ? '運営' : '通常',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: asOperator
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
