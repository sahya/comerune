import 'package:flutter/material.dart';

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
    return FloatingActionButton(
      key: const Key('comment-post-fab'),
      onPressed: onPressed,
      tooltip: 'コメントを投稿',
      // Slightly lower opacity so underlying comments remain legible through
      // the FAB, per the Issue spec ("高めの透過度").
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.55),
      foregroundColor: theme.colorScheme.onPrimary,
      child: const Icon(Icons.chat_bubble_outline),
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
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;

  /// Current selection: when user is broadcaster, defaults to operator (per
  /// issue spec). Kept on state so the selection survives draft editing.
  bool _asOperator = true;

  @override
  void initState() {
    super.initState();
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
      return;
    }
    final String text = value.text;
    final bool asOperator = widget.isBroadcaster && _asOperator;

    setState(() {
      _sending = true;
    });
    widget.onSendingChanged?.call(true);
    try {
      final CommentSendResult result = await widget.onSend(
        text: text,
        asOperator: asOperator,
        maxLength: _maxLength,
      );
      if (!mounted) {
        widget.onSendingChanged?.call(false);
        return;
      }
      if (result.isSuccess) {
        // Parent dismisses this widget; no further setState needed.
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
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
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
                            ? '運営コメントを入力'
                            : 'コメントを入力',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('comment-post-close-button'),
                    icon: const Icon(Icons.close),
                    tooltip: '閉じる',
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
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            tooltip: '送信',
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
