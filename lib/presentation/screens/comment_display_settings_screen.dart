import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../mixins/settings_screen_mixin.dart';
import '../widgets/settings_widgets.dart';

class CommentDisplaySettingsScreen extends StatefulWidget {
  const CommentDisplaySettingsScreen({
    super.key,
    required this.settingsStore,
    this.initialSettings,
  });

  final SettingsStore settingsStore;

  /// Pre-loaded settings from the parent screen.
  ///
  /// When provided, the screen uses these settings directly instead of
  /// loading from the store, avoiding a redundant read.
  final AppSettings? initialSettings;

  @override
  State<CommentDisplaySettingsScreen> createState() =>
      _CommentDisplaySettingsScreenState();
}

class _CommentDisplaySettingsScreenState
    extends State<CommentDisplaySettingsScreen>
    with SettingsScreenMixin {
  @override
  SettingsStore get settingsStore => widget.settingsStore;

  @override
  void initState() {
    super.initState();
    if (widget.initialSettings != null) {
      onSettingsLoaded(widget.initialSettings!);
      settings = widget.initialSettings;
    } else {
      loadSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (!didPop) {
          Navigator.of(context).pop(hasChanges);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('コメント表示設定')),
        body: settingsError != null
            ? buildSettingsError(context)
            : settings == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                key: const Key('comment-display-settings-list'),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: <Widget>[
                  SettingsSection(
                    title: 'コメント表示',
                    children: <Widget>[
                      SwitchListTile(
                        key: const Key('show-user-name-switch'),
                        title: const Text('ユーザー名表示'),
                        subtitle: const Text('コメントにユーザー名カラムを表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showUserName,
                        onChanged: (bool value) {
                          updateAndSave(settings.copyWith(showUserName: value));
                        },
                      ),
                      SwitchListTile(
                        key: const Key('resolve-user-name-switch'),
                        title: const Text('ユーザーID名前解決'),
                        subtitle: const Text('数値IDをニックネームに変換'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.resolveUserName,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(resolveUserName: value),
                          );
                        },
                      ),
                      SwitchListTile(
                        key: const Key('comment-two-line-switch'),
                        title: const Text('コメント二段表示'),
                        subtitle: const Text('時刻とユーザー名を1行目、コメント本文を2行目に表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.commentTwoLineEnabled,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(commentTwoLineEnabled: value),
                          );
                        },
                      ),
                      SwitchListTile(
                        key: const Key('comment-zebra-striping-switch'),
                        title: const Text('行の明暗交互表示'),
                        subtitle: const Text('コメント行ごとに背景色を交互に変え視認性を向上'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.commentZebraStripingEnabled,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(
                              commentZebraStripingEnabled: value,
                            ),
                          );
                        },
                      ),
                      SwitchListTile(
                        key: const Key('auto-save-comment-log-switch'),
                        title: const Text('コメントログ自動保存'),
                        subtitle: const Text('接続終了時にコメントをファイルに保存'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.autoSaveCommentLog,
                        onChanged: (bool value) async {
                          if (value) {
                            final String? directory =
                                await FilePicker.getDirectoryPath();
                            if (directory == null) {
                              return;
                            }
                            updateAndSave(
                              settings.copyWith(
                                autoSaveCommentLog: true,
                                autoSaveCommentLogPath: directory,
                              ),
                            );
                          } else {
                            updateAndSave(
                              settings.copyWith(autoSaveCommentLog: false),
                            );
                          }
                        },
                      ),
                      if (settings.autoSaveCommentLog)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '保存先: ${settings.autoSaveCommentLogPath.isEmpty ? '（デフォルト）' : settings.autoSaveCommentLogPath}',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      const SizedBox(height: 8),
                      SettingsIntSliderField(
                        key: const Key('comment-font-size-slider'),
                        label: 'コメント文字サイズ',
                        value: settings.commentFontSize.round(),
                        min: commentFontSizeMin.round(),
                        max: commentFontSizeMax.round(),
                        divisions: (commentFontSizeMax - commentFontSizeMin)
                            .round(),
                        suffix: 'px',
                        sweetSpotMin: 12,
                        sweetSpotMax: 18,
                        sweetSpotLabel: 'おすすめ',
                        onChanged: (int value) {
                          updateAndSave(
                            settings.copyWith(
                              commentFontSize: value.toDouble(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<PastCommentFetchCount>(
                        key: const Key('past-comment-count-dropdown'),
                        initialValue: settings.pastCommentFetchCount,
                        decoration: const InputDecoration(
                          labelText: '過去コメント取得件数',
                          border: OutlineInputBorder(),
                        ),
                        items: PastCommentFetchCount.values
                            .map(
                              (PastCommentFetchCount value) =>
                                  DropdownMenuItem<PastCommentFetchCount>(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                            )
                            .toList(),
                        onChanged: (PastCommentFetchCount? value) {
                          if (value == null) {
                            return;
                          }
                          updateAndSave(
                            settings.copyWith(pastCommentFetchCount: value),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsSection(
                    title: '統計表示',
                    children: <Widget>[
                      SwitchListTile(
                        key: const Key('statistics-enabled-switch'),
                        title: const Text('統計表示'),
                        subtitle: const Text('ステータスバーに統計情報を表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.statisticsEnabled,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(statisticsEnabled: value),
                          );
                        },
                      ),
                      SwitchListTile(
                        key: const Key('statistics-viewer-comment-switch'),
                        title: const Text('リスナー数・コメント数'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.statisticsViewerCommentEnabled,
                        onChanged: settings.statisticsEnabled
                            ? (bool value) {
                                updateAndSave(
                                  settings.copyWith(
                                    statisticsViewerCommentEnabled: value,
                                  ),
                                );
                              }
                            : null,
                      ),
                      SwitchListTile(
                        key: const Key('statistics-active-user-switch'),
                        title: const Text('5分間アクティブユーザー数'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.statisticsActiveUserEnabled,
                        onChanged: settings.statisticsEnabled
                            ? (bool value) {
                                updateAndSave(
                                  settings.copyWith(
                                    statisticsActiveUserEnabled: value,
                                  ),
                                );
                              }
                            : null,
                      ),
                      SwitchListTile(
                        key: const Key('highlight-pickup-switch'),
                        title: const Text('放送終了時の盛り上がりピックアップ'),
                        subtitle: const Text('放送終了時にピーク時間帯のコメントを自動表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.highlightPickupEnabled,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(highlightPickupEnabled: value),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
