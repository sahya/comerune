import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ng_display_subcategory.dart';
import '../mixins/settings_screen_mixin.dart';
import '../strings/app_strings.dart';
import '../widgets/display_subcategory_warning_dialog.dart';
import '../widgets/settings_widgets.dart';

final List<bool Function(AppSettings)> _messageTypeGetters =
    <bool Function(AppSettings)>[
      (AppSettings s) => s.showOperatorComment,
      (AppSettings s) => s.showSystemMessage,
      (AppSettings s) => s.showEmotion,
      (AppSettings s) => s.showGiftComment,
      (AppSettings s) => s.showNicoadComment,
    ];

int _enabledMessageTypeCount(AppSettings settings) {
  return _messageTypeGetters
      .where((bool Function(AppSettings) g) => g(settings))
      .length;
}

/// Declarative spec for one "読み上げ対象外コメントの表示" toggle. Kept at file
/// scope so the 4 toggles share a single source of truth between the build
/// method and the `N / 4 表示中` subtitle helper.
@immutable
class _NgDisplayToggleSpec {
  const _NgDisplayToggleSpec({
    required this.subcategory,
    required this.key,
    required this.title,
    required this.subtitle,
    required this.get,
    required this.set,
  });

  final NgDisplaySubcategory subcategory;
  final Key key;
  final String title;
  final String subtitle;
  final bool Function(AppSettings s) get;
  final AppSettings Function(AppSettings s, bool value) set;
}

const List<_NgDisplayToggleSpec> _ngDisplayToggleSpecs = <_NgDisplayToggleSpec>[
  _NgDisplayToggleSpec(
    subcategory: NgDisplaySubcategory.violence,
    key: Key('show-violent-comment-switch'),
    title: '暴力表現を含むコメントを表示',
    subtitle: '殺害・傷害などの表現を含むコメントを画面に表示します（読み上げは行いません）',
    get: _getShowViolent,
    set: _setShowViolent,
  ),
  _NgDisplayToggleSpec(
    subcategory: NgDisplaySubcategory.sexual,
    key: Key('show-sexual-comment-switch'),
    title: '性的表現を含むコメントを表示',
    subtitle: '露骨な性的表現を含むコメントを画面に表示します（読み上げは行いません）',
    get: _getShowSexual,
    set: _setShowSexual,
  ),
  _NgDisplayToggleSpec(
    subcategory: NgDisplaySubcategory.discrimination,
    key: Key('show-discrimination-comment-switch'),
    title: '差別・ヘイト表現を含むコメントを表示',
    subtitle: '差別・ヘイト的な表現を含むコメントを画面に表示します（読み上げは行いません）',
    get: _getShowDiscrimination,
    set: _setShowDiscrimination,
  ),
  _NgDisplayToggleSpec(
    subcategory: NgDisplaySubcategory.minors,
    key: Key('show-minors-comment-switch'),
    title: '未成年関連表現を含むコメントを表示',
    subtitle: '児童・未成年に関する不適切な表現を含むコメントを画面に表示します（読み上げは行いません）',
    get: _getShowMinors,
    set: _setShowMinors,
  ),
];

bool _getShowViolent(AppSettings s) => s.showViolentComment;
AppSettings _setShowViolent(AppSettings s, bool v) =>
    s.copyWith(showViolentComment: v);
bool _getShowSexual(AppSettings s) => s.showSexualComment;
AppSettings _setShowSexual(AppSettings s, bool v) =>
    s.copyWith(showSexualComment: v);
bool _getShowDiscrimination(AppSettings s) => s.showDiscriminationComment;
AppSettings _setShowDiscrimination(AppSettings s, bool v) =>
    s.copyWith(showDiscriminationComment: v);
bool _getShowMinors(AppSettings s) => s.showMinorsRelatedComment;
AppSettings _setShowMinors(AppSettings s, bool v) =>
    s.copyWith(showMinorsRelatedComment: v);

int _enabledNgDisplayCount(AppSettings settings) {
  int n = 0;
  for (final _NgDisplayToggleSpec spec in _ngDisplayToggleSpecs) {
    if (spec.get(settings)) n++;
  }
  return n;
}

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

  /// Handles OFF→ON / ON→OFF taps on the NG display subcategory toggles.
  ///
  /// OFF→ON always shows [showDisplaySubcategoryWarningDialog] first; the
  /// setting is only persisted when the user confirms. ON→OFF persists
  /// immediately with no confirmation — the restrictive state never needs
  /// to be double-checked.
  Future<void> _onNgDisplayToggleChanged({
    required _NgDisplayToggleSpec spec,
    required AppSettings settings,
    required bool value,
  }) async {
    if (!value) {
      updateAndSave(spec.set(settings, false));
      return;
    }
    final bool confirmed = await showDisplaySubcategoryWarningDialog(
      context: context,
      subcategory: spec.subcategory,
    );
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      return;
    }
    updateAndSave(spec.set(settings, true));
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
                      const SizedBox(height: 12),
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
                      // 二段表示が ON のときだけ意味があるサブ設定なので、
                      // OFF 時は UI を隠して画面ノイズを減らす（OFF→ON した
                      // 際は、保存済みの値で再表示される）。
                      if (settings.commentTwoLineEnabled) ...<Widget>[
                        const SizedBox(height: 4),
                        SettingsIntSliderField(
                          key: const Key(
                            'comment-two-line-meta-font-percent-slider',
                          ),
                          label: '上段の文字サイズ（本文比）',
                          value: settings.commentTwoLineMetaFontPercent,
                          min: commentTwoLineMetaFontPercentMin,
                          max: commentTwoLineMetaFontPercentMax,
                          divisions:
                              commentTwoLineMetaFontPercentMax -
                              commentTwoLineMetaFontPercentMin,
                          suffix: '%',
                          sweetSpotMin: 35,
                          sweetSpotMax: 60,
                          sweetSpotLabel: 'おすすめ',
                          onChanged: (int value) {
                            updateAndSave(
                              settings.copyWith(
                                commentTwoLineMetaFontPercent: value,
                              ),
                            );
                          },
                        ),
                        // Discloses the absolute 9px floor so users who pick
                        // very low percentages don't think the slider is
                        // broken when the rendered size stops shrinking.
                        Padding(
                          key: const Key(
                            'comment-two-line-meta-font-percent-note',
                          ),
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Text(
                            '※ 視認性確保のため、最小サイズの制約により小さい%でも一定以下にはなりません。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
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
                      // Issue #784. Subtitle:
                      //   - 「コメント番号」「時刻の前」のユーザー向け表現に
                      //     とどめ、`NDGR Chat.no` のような内部仕様は出さない
                      //     (CLAUDE.md の「内部実装の詳細を表示しない」方針)。
                      //   - Legacy WebSocket 経路では現状番号が出ない事実を
                      //     明示し、視聴中に番号が表示されない配信があっても
                      //     ユーザーが「壊れている」と誤解しないようにする。
                      SwitchListTile(
                        key: const Key('comment-show-comment-no-switch'),
                        title: const Text('コメント番号を表示'),
                        subtitle: const Text(
                          'コメント番号を時刻の前に表示します（一部の配信や種類の'
                          'コメントでは番号が付きません）',
                        ),
                        contentPadding: EdgeInsets.zero,
                        value: settings.showCommentNo,
                        onChanged: (bool value) {
                          updateAndSave(
                            settings.copyWith(showCommentNo: value),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
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
                      Padding(
                        key: const Key('past-comment-count-description'),
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          AppStrings.commentDisplaySettings
                              .pastCommentFetchCountDescription(
                                liveCommentBufferSize:
                                    timelineLiveCommentBufferSize,
                              ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      ExpansionTile(
                        key: const Key('message-type-expansion-tile'),
                        title: const Text('表示するメッセージ種別'),
                        subtitle: Text(
                          '${_enabledMessageTypeCount(settings)} / ${_messageTypeGetters.length} 表示中',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(
                          left: 16,
                          top: 8,
                          bottom: 8,
                        ),
                        initiallyExpanded: false,
                        children: <Widget>[
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: <Widget>[
                              FilterChip(
                                key: const Key('show-operator-comment-chip'),
                                label: const Text('運営'),
                                selected: settings.showOperatorComment,
                                onSelected: (bool value) {
                                  updateAndSave(
                                    settings.copyWith(
                                      showOperatorComment: value,
                                    ),
                                  );
                                },
                              ),
                              FilterChip(
                                key: const Key('show-system-message-chip'),
                                label: const Text('システム'),
                                selected: settings.showSystemMessage,
                                onSelected: (bool value) {
                                  updateAndSave(
                                    settings.copyWith(showSystemMessage: value),
                                  );
                                },
                              ),
                              FilterChip(
                                key: const Key('show-emotion-chip'),
                                label: const Text('エモーション'),
                                selected: settings.showEmotion,
                                onSelected: (bool value) {
                                  updateAndSave(
                                    settings.copyWith(showEmotion: value),
                                  );
                                },
                              ),
                              FilterChip(
                                key: const Key('show-gift-comment-chip'),
                                label: const Text('ギフト'),
                                selected: settings.showGiftComment,
                                onSelected: (bool value) {
                                  updateAndSave(
                                    settings.copyWith(showGiftComment: value),
                                  );
                                },
                              ),
                              FilterChip(
                                key: const Key('show-nicoad-comment-chip'),
                                label: const Text('ニコニ広告'),
                                selected: settings.showNicoadComment,
                                onSelected: (bool value) {
                                  updateAndSave(
                                    settings.copyWith(showNicoadComment: value),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('ng-display-expansion-tile'),
                        title: const Text('読み上げ対象外コメントの表示'),
                        subtitle: Text(
                          '${_enabledNgDisplayCount(settings)} / ${_ngDisplayToggleSpecs.length} 表示中 ・ 有効にしても音声では読み上げられません',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(
                          left: 16,
                          top: 4,
                          bottom: 4,
                        ),
                        initiallyExpanded: false,
                        children: <Widget>[
                          for (final _NgDisplayToggleSpec spec
                              in _ngDisplayToggleSpecs)
                            SwitchListTile(
                              key: spec.key,
                              title: Text(spec.title),
                              subtitle: Text(spec.subtitle),
                              contentPadding: EdgeInsets.zero,
                              value: spec.get(settings),
                              onChanged: (bool value) =>
                                  _onNgDisplayToggleChanged(
                                    spec: spec,
                                    settings: settings,
                                    value: value,
                                  ),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        key: const Key('auto-save-comment-log-switch'),
                        title: const Text('コメントログ自動保存'),
                        subtitle: const Text('接続終了時にコメントをファイルに保存'),
                        contentPadding: EdgeInsets.zero,
                        value: settings.autoSaveCommentLog,
                        onChanged: (bool value) async {
                          if (value) {
                            // SAF オプション付きの `androidOptions` を渡さないこと
                            // （file_picker 12 時点の挙動）。渡した場合、戻り値が実ファイル
                            // パスではなく content:// URI 文字列に変わり、保存先を
                            // `Directory` として直接扱っている自動保存が実行時に壊れる。
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
