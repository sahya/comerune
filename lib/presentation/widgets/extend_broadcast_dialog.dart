import 'package:flutter/material.dart';

import '../../app_logging.dart';
import '../strings/app_strings.dart';

/// 「放送を延長」ダイアログで選べる固定肢（分）。
///
/// 上限ガードはクライアントでは行わず、サーバ判定に委ねる方針（Issue #872）。
/// 残り枠の動的フィルタや「まとめて延長」項目は会員レベル取得を前提と
/// する後続 Issue で導入する。
const List<int> kExtendBroadcastOptionsMinutes = <int>[
  30,
  60,
  90,
  120,
  180,
  210,
];

/// 既定で選択される分数。
const int kExtendBroadcastDefaultMinutes = 30;

/// 「延長する」押下時に呼び出されるコールバック。
///
/// 戻り値で API 呼び出しの成否を返す。`true` のときダイアログは
/// 「成功」結果でクローズされ、`false` のとき「失敗」結果でクローズされる。
typedef ExtendBroadcastConfirmCallback = Future<bool> Function(int minutes);

/// ダイアログのクローズ理由を表す結果オブジェクト。
///
/// `null`（= ダイアログがキャンセルされた）と区別するため、結果は
/// 必ず非 `null` で返り、`success` フラグで成功・失敗を区別する。
class ExtendBroadcastDialogResult {
  const ExtendBroadcastDialogResult({
    required this.success,
    required this.minutes,
  });

  /// 延長 API が成功したか。
  final bool success;

  /// ユーザーが選択した分数（成功・失敗いずれの場合も値を持つ）。
  final int minutes;
}

/// 「放送を延長」ダイアログを表示する。
///
/// - 戻り値が `null`: ユーザーがキャンセルした（背景タップ・キャンセル
///   ボタン・バックキー含む）。
/// - 戻り値が非 `null`: ユーザーが「延長する」を押下し、`onConfirm` の
///   結果が確定した（`success` で成否を判定）。
Future<ExtendBroadcastDialogResult?> showExtendBroadcastDialog(
  BuildContext context, {
  required ExtendBroadcastConfirmCallback onConfirm,
}) {
  return showDialog<ExtendBroadcastDialogResult>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return ExtendBroadcastDialog(onConfirm: onConfirm);
    },
  );
}

/// 配信者が放送を任意分数延長するためのダイアログ。
///
/// プルダウンで 30/60/90/120/180/210 分から選択し、「延長する」を押すと
/// [onConfirm] が呼ばれる。`onConfirm` が解決するまでの間はプルダウンと
/// 両ボタンが無効化され、「延長する」ボタン内に進捗インジケータが表示
/// される。`onConfirm` 完了後、戻り値（成功/失敗）を含む
/// [ExtendBroadcastDialogResult] でダイアログがクローズされる。
class ExtendBroadcastDialog extends StatefulWidget {
  const ExtendBroadcastDialog({required this.onConfirm, super.key});

  final ExtendBroadcastConfirmCallback onConfirm;

  @override
  State<ExtendBroadcastDialog> createState() => _ExtendBroadcastDialogState();
}

class _ExtendBroadcastDialogState extends State<ExtendBroadcastDialog> {
  int _selectedMinutes = kExtendBroadcastDefaultMinutes;
  bool _isInFlight = false;

  Future<void> _onConfirm() async {
    if (_isInFlight) {
      return;
    }
    setState(() {
      _isInFlight = true;
    });
    bool success = false;
    try {
      // Defensive try-catch around the host callback: a stray exception
      // thrown after the dialog has already been popped (in `finally`)
      // would otherwise leave the screen with an unhandled future and
      // misrepresent the API outcome. Convert any exception into a
      // failure result so the screen-side handler always sees a
      // consistent 2-値 outcome.
      success = await widget.onConfirm(_selectedMinutes);
    } catch (e, st) {
      // Preserve diagnostics: the Repository normally swallows its own
      // exceptions into BroadcastControlResult, so anything reaching
      // here is genuinely unexpected (programming error, host-side
      // state mutation, etc). Log via the project-wide debug channel
      // so field issues are reproducible.
      appDebugLogLazy(() => '[ExtendBroadcastDialog] onConfirm threw: $e\n$st');
      success = false;
    } finally {
      if (mounted) {
        Navigator.of(context).pop(
          ExtendBroadcastDialogResult(
            success: success,
            minutes: _selectedMinutes,
          ),
        );
      }
    }
  }

  void _onCancel() {
    if (_isInFlight) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ExtendBroadcastStrings strings = AppStrings.extendBroadcast;

    // API 待機中はダイアログ自体を背景タップ・バックキーで閉じさせない。
    return PopScope<ExtendBroadcastDialogResult>(
      canPop: !_isInFlight,
      child: AlertDialog(
        key: const Key('extend-broadcast-dialog'),
        title: Text(strings.dialogTitle),
        content: Semantics(
          container: true,
          label: '${strings.fieldLabel}、現在 $_selectedMinutes 分、ボタン',
          child: DropdownButtonFormField<int>(
            key: const Key('extend-broadcast-minutes-dropdown'),
            initialValue: _selectedMinutes,
            decoration: InputDecoration(
              labelText: strings.fieldLabel,
              border: const OutlineInputBorder(),
            ),
            onChanged: _isInFlight
                ? null
                : (int? value) {
                    if (value == null) return;
                    setState(() {
                      _selectedMinutes = value;
                    });
                  },
            items: <DropdownMenuItem<int>>[
              for (final int minutes in kExtendBroadcastOptionsMinutes)
                DropdownMenuItem<int>(
                  key: Key('extend-broadcast-option-$minutes'),
                  value: minutes,
                  child: Text(strings.optionMinutes(minutes)),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('extend-broadcast-cancel-button'),
            onPressed: _isInFlight ? null : _onCancel,
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('extend-broadcast-confirm-button'),
            onPressed: _isInFlight ? null : _onConfirm,
            child: _isInFlight
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: '延長中',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(strings.confirm),
                    ],
                  )
                : Text(strings.confirm),
          ),
        ],
      ),
    );
  }
}
