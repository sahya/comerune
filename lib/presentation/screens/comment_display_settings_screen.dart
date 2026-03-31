import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../widgets/settings_widgets.dart';

class CommentDisplaySettingsScreen extends StatefulWidget {
  const CommentDisplaySettingsScreen({
    super.key,
    required this.settingsStore,
  });

  final SettingsStore settingsStore;

  @override
  State<CommentDisplaySettingsScreen> createState() =>
      _CommentDisplaySettingsScreenState();
}

class _CommentDisplaySettingsScreenState
    extends State<CommentDisplaySettingsScreen> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final AppSettings loaded = await widget.settingsStore.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _settings = loaded;
    });
  }

  void _updateAndSave(AppSettings next) {
    setState(() {
      _settings = next;
    });
    unawaited(_saveSettings(next));
  }

  Future<void> _saveSettings(AppSettings next) =>
      saveSettingsToStore(widget.settingsStore, next);

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('コメント表示設定'),
      ),
      body: settings == null
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
                        _updateAndSave(settings.copyWith(showUserName: value));
                      },
                    ),
                    SwitchListTile(
                      key: const Key('resolve-user-name-switch'),
                      title: const Text('ユーザーID名前解決'),
                      subtitle: const Text('数値IDをニックネームに変換'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.resolveUserName,
                      onChanged: settings.showUserName
                          ? (bool value) {
                              _updateAndSave(
                                  settings.copyWith(resolveUserName: value));
                            }
                          : null,
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
                              await FilePicker.platform.getDirectoryPath();
                          if (directory == null) {
                            return;
                          }
                          _updateAndSave(settings.copyWith(
                            autoSaveCommentLog: true,
                            autoSaveCommentLogPath: directory,
                          ));
                        } else {
                          _updateAndSave(
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
                      divisions:
                          (commentFontSizeMax - commentFontSizeMin).round(),
                      suffix: 'px',
                      sweetSpotMin: 12,
                      sweetSpotMax: 18,
                      sweetSpotLabel: 'おすすめ',
                      onChanged: (int value) {
                        _updateAndSave(
                          settings.copyWith(commentFontSize: value.toDouble()),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<PastCommentFetchCount>(
                      key: const Key('past-comment-count-dropdown'),
                      value: settings.pastCommentFetchCount,
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
                        _updateAndSave(
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
                        _updateAndSave(
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
                              _updateAndSave(
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
                              _updateAndSave(
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
                        _updateAndSave(
                          settings.copyWith(highlightPickupEnabled: value),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
