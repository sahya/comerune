import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/app_update/update_prompt_store.dart';
import '../../domain/models/app_update.dart';
import '../strings/app_strings.dart';

/// 判定結果に応じて更新 UI を提示する。
///
/// - [UpdateRequirement.forced]: 閉じられないブロック画面（更新ボタンのみ）。
/// - [UpdateRequirement.optional]: あとで閉じられるダイアログ。
///   起動時は見送り版を再表示しない（[bypassDismissed] が false）。
///   設定画面の手動確認では常に表示する（[bypassDismissed] が true）。
/// - [UpdateRequirement.none]: 何もしない。
Future<void> presentUpdateStatus({
  required BuildContext context,
  required UpdateStatus status,
  required UpdatePromptStore promptStore,
  bool bypassDismissed = false,
}) async {
  switch (status.requirement) {
    case UpdateRequirement.none:
      return;
    case UpdateRequirement.forced:
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (BuildContext dialogContext) {
          return PopScope(
            canPop: false,
            child: _ForcedUpdateBlocker(
              version: status.latestVersion?.toString(),
              releaseUrl: status.releaseUrl,
            ),
          );
        },
      );
      return;
    case UpdateRequirement.optional:
      final String version = status.latestVersion?.toString() ?? '';
      if (!bypassDismissed && !promptStore.shouldPrompt(version)) {
        return;
      }
      final bool? update = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(AppStrings.appUpdate.optionalTitle),
            content: Text(AppStrings.appUpdate.optionalMessage(version)),
            actions: <Widget>[
              TextButton(
                key: const Key('app-update-later'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppStrings.appUpdate.laterButton),
              ),
              TextButton(
                key: const Key('app-update-now'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(AppStrings.appUpdate.updateButton),
              ),
            ],
          );
        },
      );
      if (update ?? false) {
        if (!context.mounted) {
          return;
        }
        await _openReleaseUrl(context, status.releaseUrl);
      } else {
        // 「後で」または barrier 外タップ。同一版で再通知しない。
        if (version.isNotEmpty) {
          await promptStore.setDismissedVersion(version);
        }
      }
      return;
  }
}

/// 配布ページを外部ブラウザで開く（副作用は起動のみ）。開けたら true。
///
/// `url` が null / 不正、または `url_launcher` が例外（対応ブラウザ不在
/// 等）の場合は false。`Error` は伝搬させる。
Future<bool> _launchReleaseUrl(String? url) async {
  final Uri? uri = url == null ? null : Uri.tryParse(url);
  if (uri == null) {
    return false;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception catch (e) {
    log('launchUrl threw (${e.runtimeType})', name: 'AppUpdate');
    return false;
  }
}

/// 任意更新ダイアログ用: 起動を試み、失敗時は SnackBar で通知する。
///
/// 任意ダイアログは通常の Scaffold 上で表示されるため SnackBar が見える。
Future<void> _openReleaseUrl(BuildContext context, String? url) async {
  final bool launched = await _launchReleaseUrl(url);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppStrings.appUpdate.launchFailed)),
      );
  }
}

/// 強制更新時に操作をブロックする全画面ダイアログ。
///
/// ユーザーは画面を離脱できないため、起動失敗時の通知に SnackBar は使えない
/// （フルスクリーン Dialog の背後の Scaffold に出て見えない）。失敗は
/// **画面内インライン**で提示し、ボタンは再試行可能なまま残す。
class _ForcedUpdateBlocker extends StatefulWidget {
  const _ForcedUpdateBlocker({required this.version, required this.releaseUrl});

  final String? version;
  final String? releaseUrl;

  @override
  State<_ForcedUpdateBlocker> createState() => _ForcedUpdateBlockerState();
}

class _ForcedUpdateBlockerState extends State<_ForcedUpdateBlocker> {
  bool _launching = false;
  bool _launchFailed = false;

  Future<void> _onUpdatePressed() async {
    if (_launching) {
      return;
    }
    setState(() {
      _launching = true;
      _launchFailed = false;
    });
    final bool launched = await _launchReleaseUrl(widget.releaseUrl);
    if (!mounted) {
      return;
    }
    setState(() {
      _launching = false;
      _launchFailed = !launched;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String message = widget.version == null
        ? AppStrings.appUpdate.forcedMessage
        : AppStrings.appUpdate.forcedMessageWithVersion(widget.version!);
    return Dialog.fullscreen(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.system_update, size: 56),
              const SizedBox(height: 16),
              Text(
                AppStrings.appUpdate.forcedTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('app-update-forced-now'),
                onPressed: _launching ? null : _onUpdatePressed,
                child: _launching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(AppStrings.appUpdate.updateButton),
              ),
              if (_launchFailed) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  AppStrings.appUpdate.launchFailed,
                  key: const Key('app-update-forced-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
