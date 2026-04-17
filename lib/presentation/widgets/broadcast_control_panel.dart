import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/broadcast_control_result.dart';
import '../../domain/models/follow_program.dart';
import '../errors/user_facing_error_messages.dart';

/// Callback for broadcast control operations.
///
/// Returns `true` if the operation was successful.
typedef BroadcastControlCallback = Future<BroadcastControlResult> Function();

/// Panel that shows broadcast control actions for the user's own program.
///
/// Displays contextual actions based on program status:
/// - [ProgramStatus.reserved] / [ProgramStatus.test]: "Start broadcast" button
///   with a 3-2-1 countdown overlay.
/// - [ProgramStatus.onAir]: "End broadcast" slide-to-confirm control.
class BroadcastControlPanel extends StatelessWidget {
  const BroadcastControlPanel({
    required this.program,
    required this.onStart,
    required this.onEnd,
    this.enabled = true,
    super.key,
  });

  final FollowProgram program;
  final BroadcastControlCallback onStart;
  final BroadcastControlCallback onEnd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ProgramStatus? status = program.status;

    if (status == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 放送開始ボタンは実装済みだが、API の実機検証が完了するまで非表示。
          // 有効化するには以下のコメントを外す:
          // if (program.canStart)
          //   _StartBroadcastButton(
          //     enabled: enabled,
          //     onStart: onStart,
          //   ),
          if (program.canEnd)
            _SlideToEndBroadcast(enabled: enabled, onEnd: onEnd),
          if (program.canEnd && program.endAt != null)
            _RemainingTimeIndicator(endAt: program.endAt!),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Start broadcast button with countdown overlay
// ---------------------------------------------------------------------------

class _StartBroadcastButton extends StatefulWidget {
  const _StartBroadcastButton({required this.enabled, required this.onStart});

  final bool enabled;
  final BroadcastControlCallback onStart;

  @override
  State<_StartBroadcastButton> createState() => _StartBroadcastButtonState();
}

class _StartBroadcastButtonState extends State<_StartBroadcastButton> {
  bool _isLoading = false;

  Future<void> _onPressed() async {
    final bool? confirmed = await _showCountdownDialog(context);
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final BroadcastControlResult result = await widget.onStart();
      if (!mounted) {
        return;
      }
      if (result.success) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('放送を開始しました')));
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(userFacingBroadcastError('開始', result))),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: widget.enabled && !_isLoading ? _onPressed : null,
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.play_arrow_rounded),
      label: const Text('放送を開始'),
    );
  }
}

/// Shows a 3-2-1 countdown dialog before starting.
///
/// Returns `true` if the countdown completed without cancellation.
Future<bool?> _showCountdownDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return const _CountdownDialog();
    },
  );
}

class _CountdownDialog extends StatefulWidget {
  const _CountdownDialog();

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog>
    with SingleTickerProviderStateMixin {
  static const int _countdownSeconds = 3;
  int _remaining = _countdownSeconds;
  Timer? _timer;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scaleController, curve: Curves.easeOut));
    _scaleController.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final int next = _remaining - 1;
      if (next <= 0) {
        _timer?.cancel();
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _remaining = next;
      });
      HapticFeedback.lightImpact();
      _scaleController
        ..reset()
        ..forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('放送を開始します', style: theme.textTheme.titleMedium),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            label: '$_remaining',
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: ExcludeSemantics(
                  child: Text(
                    '$_remaining',
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Slide-to-end broadcast control
// ---------------------------------------------------------------------------

class _SlideToEndBroadcast extends StatefulWidget {
  const _SlideToEndBroadcast({required this.enabled, required this.onEnd});

  final bool enabled;
  final BroadcastControlCallback onEnd;

  @override
  State<_SlideToEndBroadcast> createState() => _SlideToEndBroadcastState();
}

class _SlideToEndBroadcastState extends State<_SlideToEndBroadcast> {
  double _dragExtent = 0;
  bool _isLoading = false;
  static const double _threshold = 0.85;

  static const double _thumbSize = 48;

  double get _trackWidth {
    // Account for padding (16*2) + internal padding (2*2) + thumb size.
    final double screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth - 32 - 4 - _thumbSize;
  }

  double get _progress => (_dragExtent / _trackWidth).clamp(0.0, 1.0);

  Future<void> _onThresholdReached() async {
    HapticFeedback.heavyImpact();
    setState(() {
      _isLoading = true;
      _dragExtent = 0;
    });

    try {
      final BroadcastControlResult result = await widget.onEnd();
      if (!mounted) {
        return;
      }
      if (result.success) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('放送を終了しました')));
      } else if (result.isAlreadyEnded) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('放送は既に終了しています')));
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(userFacingBroadcastError('終了', result))),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = widget.enabled && !_isLoading;

    return Semantics(
      label: _isLoading ? '放送を終了しています' : 'スライドして放送を終了',
      value: _isLoading ? null : '${(_progress * 100).round()}%',
      excludeSemantics: true,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: active
              ? Color.lerp(
                  theme.colorScheme.errorContainer,
                  theme.colorScheme.error,
                  _progress,
                )
              : theme.disabledColor.withValues(alpha: 0.12),
        ),
        child: Stack(
          children: <Widget>[
            // Background label
            Center(
              child: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    )
                  : Text(
                      'スライドして放送を終了',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: active
                            ? Color.lerp(
                                theme.colorScheme.onErrorContainer,
                                theme.colorScheme.onError,
                                _progress,
                              )
                            : theme.disabledColor,
                      ),
                    ),
            ),
            // Draggable thumb
            if (active)
              Positioned(
                left: _dragExtent + 4,
                top: (56 - _thumbSize) / 2,
                child: GestureDetector(
                  onHorizontalDragUpdate: (DragUpdateDetails details) {
                    if (_isLoading) {
                      return;
                    }
                    setState(() {
                      _dragExtent = (_dragExtent + details.delta.dx).clamp(
                        0.0,
                        _trackWidth,
                      );
                    });
                    if (_progress >= _threshold) {
                      unawaited(_onThresholdReached());
                    }
                  },
                  onHorizontalDragEnd: (_) {
                    if (_progress < _threshold) {
                      setState(() => _dragExtent = 0);
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.error,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.stop_rounded,
                      color: theme.colorScheme.onError,
                      size: 24,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Remaining time indicator
// ---------------------------------------------------------------------------

class _RemainingTimeIndicator extends StatefulWidget {
  const _RemainingTimeIndicator({required this.endAt});

  final DateTime endAt;

  @override
  State<_RemainingTimeIndicator> createState() =>
      _RemainingTimeIndicatorState();
}

class _RemainingTimeIndicatorState extends State<_RemainingTimeIndicator> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration remaining = widget.endAt.difference(DateTime.now());

    if (remaining.isNegative) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '放送終了時間を過ぎました',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final int totalSeconds = remaining.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    final String label = hours > 0
        ? '残り $hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '残り ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    // Warn when under 5 minutes.
    final bool isUrgent = remaining.inMinutes < 5;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.timer_outlined,
            size: 14,
            color: isUrgent
                ? theme.colorScheme.error
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isUrgent
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
              fontWeight: isUrgent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
