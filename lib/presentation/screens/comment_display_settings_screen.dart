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
                      // Group the three message-type display toggles
                      // (operator / system / emotion) under a dedicated
                      // subheader so they read as a related cluster rather
                      // than as loose switches mixed in with unrelated
                      // display/layout options above. The Card-based
                      // `SettingsSection` already provides the outer
                      // container; we just introduce a divider + label
                      // inside it (consistent with how sections visually
                      // break inside a grouped list on Material surfaces).
                      const Divider(
                        key: Key('message-type-display-divider'),
                        height: 24,
                      ),
                      Padding(
                        key: const Key('message-type-display-header'),
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '表示するメッセージ種別',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      SwitchListTile(
                        key: const Key('show-operator-comment-switch'),
                        title: const Text('運営コメントを表示'),
                        subtitle: const Text('配信者の運営コメント（マーキー）をコメント一覧に表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showOperatorComment,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(showOperatorComment: value),
                          );
                        },
                      ),
                      SwitchListTile(
                        key: const Key('show-system-message-switch'),
                        title: const Text('システムメッセージを表示'),
                        subtitle: const Text('ニコニコ市場などのシステム通知を表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showSystemMessage,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(showSystemMessage: value),
                          );
                        },
                      ),
                      SwitchListTile(
                        key: const Key('show-emotion-switch'),
                        title: const Text('エモーションを表示'),
                        subtitle: const Text('視聴者のエモーション通知を表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showEmotion,
                        onChanged: (bool value) {
                          updateAndSave(settings.copyWith(showEmotion: value));
                        },
                      ),
                      SwitchListTile(
                        key: const Key('show-gift-comment-switch'),
                        title: const Text('ギフトコメントを表示'),
                        subtitle: const Text('視聴者からのギフト通知を表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showGiftComment,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(showGiftComment: value),
                          );
                        },
                      ),
                      SwitchListTile(
                        key: const Key('show-nicoad-comment-switch'),
                        title: const Text('ニコニ広告コメントを表示'),
                        subtitle: const Text('ニコニ広告の通知コメントを表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showNicoadComment,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(showNicoadComment: value),
                          );
                        },
                      ),
                      const Divider(
                        key: Key('message-type-display-divider-end'),
                        height: 24,
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
                    title: 'コメントの強調表示',
                    children: <Widget>[
                      SwitchListTile(
                        key: const Key('emphasize-gift-nicoad-switch'),
                        title: const Text('ギフト・ニコニ広告の強調表示'),
                        subtitle: const Text('薄い網掛け背景とアイコンで種別を分かりやすく表示'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.emphasizeGiftNicoadComment,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(
                              emphasizeGiftNicoadComment: value,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsSection(
                    title: '保護通知',
                    children: <Widget>[
                      SwitchListTile(
                        key: const Key(
                          'ng-protection-notification-enabled-switch',
                        ),
                        title: const Text('保護通知を有効化'),
                        subtitle: const Text(
                          'NGワード/NGユーザーでコメントをフィルタした時にスナックバーとバッジで通知します',
                        ),
                        contentPadding: EdgeInsets.zero,
                        value: settings.ngProtectionNotificationEnabled,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(
                              ngProtectionNotificationEnabled: value,
                            ),
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          '配信画面に映り込むリスクがあります。配信しながら使う場合はご注意ください。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
