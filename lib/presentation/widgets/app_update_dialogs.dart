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

/// 配布ページを外部ブラウザで開く。開けない場合はスナックバーで通知し
/// false を返す。
Future<bool> _openReleaseUrl(BuildContext context, String? url) async {
  final Uri? uri = url == null ? null : Uri.tryParse(url);
  bool launched = false;
  if (uri != null) {
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      // url_launcher は対応ブラウザ不在等で例外を投げ得る。種別のみ記録。
      log('launchUrl threw (${e.runtimeType})', name: 'AppUpdate');
      launched = false;
    }
  }
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppStrings.appUpdate.launchFailed)),
      );
  }
  return launched;
}

/// 強制更新時に操作をブロックする全画面ダイアログ。
class _ForcedUpdateBlocker extends StatelessWidget {
  const _ForcedUpdateBlocker({required this.version, required this.releaseUrl});

  final String? version;
  final String? releaseUrl;

  @override
  Widget build(BuildContext context) {
    final String message = version == null
        ? AppStrings.appUpdate.forcedMessage
        : AppStrings.appUpdate.forcedMessageWithVersion(version!);
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
                onPressed: () => _openReleaseUrl(context, releaseUrl),
                child: Text(AppStrings.appUpdate.updateButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
