import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/comment_log/broadcast_history_store.dart';
import '../../domain/comment_log/broadcast_history_entry.dart';
import '../../domain/comment_log/comment_log_stats.dart';
import '../strings/app_strings.dart';

/// Issue #766: 過去放送のコメント統計を再アクセスできる履歴ビュー。
///
/// - 端末ローカルにのみ保存され、外部送信はされない
/// - 自分の放送のみ記録（視聴のみは保存しない）
/// - 上限 [SharedPreferencesBroadcastHistoryStore.defaultMaxEntries] 件、超過分は古いものから破棄
class BroadcastHistoryScreen extends StatefulWidget {
  const BroadcastHistoryScreen({super.key, required this.store});

  final BroadcastHistoryStore store;

  @override
  State<BroadcastHistoryScreen> createState() => _BroadcastHistoryScreenState();
}

class _BroadcastHistoryScreenState extends State<BroadcastHistoryScreen> {
  late List<BroadcastHistoryEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.store.loadAll();
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = widget.store.loadAll();
    });
  }

  Future<void> _confirmAndClearAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          key: const Key('broadcast-history-clear-all-dialog'),
          title: Text(AppStrings.broadcastHistory.clearAllDialogTitle),
          content: Text(AppStrings.broadcastHistory.clearAllDialogMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppStrings.broadcastHistory.clearAllDialogCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppStrings.broadcastHistory.clearAllDialogConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await widget.store.clearAll();
    if (!mounted) {
      return;
    }
    _reload();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: const Key('broadcast-history-cleared-snackbar'),
          content: Text(AppStrings.broadcastHistory.clearAllSnackBar),
        ),
      );
  }

  Future<void> _removeOne(BroadcastHistoryEntry entry) async {
    await widget.store.removeByLv(entry.lv);
    if (!mounted) {
      return;
    }
    _reload();
  }

  Future<void> _openProgramPage(BroadcastHistoryEntry entry) async {
    final Uri? uri = Uri.tryParse(entry.programPageUrl);
    bool launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to launch program page',
          name: 'BroadcastHistoryScreen',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            key: const Key('broadcast-history-launch-failed-snackbar'),
            content: Text(AppStrings.broadcastHistory.launchFailedSnackBar),
          ),
        );
    }
  }

  void _showEntryDetail(BroadcastHistoryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return _BroadcastHistoryDetailSheet(
          entry: entry,
          onOpenProgramPage: () {
            Navigator.of(sheetContext).pop();
            unawaited(_openProgramPage(entry));
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<BroadcastHistoryEntry> entries = _entries;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.broadcastHistory.screenTitle),
        actions: <Widget>[
          if (entries.isNotEmpty)
            IconButton(
              key: const Key('broadcast-history-clear-all-button'),
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: AppStrings.broadcastHistory.clearAllTooltip,
              onPressed: _confirmAndClearAll,
            ),
        ],
      ),
      body: entries.isEmpty
          ? _buildEmpty(context)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    AppStrings.broadcastHistory.privacyNote,
                    key: const Key('broadcast-history-privacy-note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    key: const Key('broadcast-history-list'),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext _, int index) {
                      final BroadcastHistoryEntry entry = entries[index];
                      return Dismissible(
                        key: ValueKey<String>(
                          'broadcast-history-entry-${entry.lv}-'
                          '${entry.recordedAt.toIso8601String()}',
                        ),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          color: Theme.of(context).colorScheme.error,
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        confirmDismiss: (_) async {
                          final bool? confirmed = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext dialogContext) {
                              return AlertDialog(
                                key: const Key(
                                  'broadcast-history-remove-one-dialog',
                                ),
                                title: Text(
                                  AppStrings
                                      .broadcastHistory
                                      .removeOneDialogTitle,
                                ),
                                content: Text(
                                  AppStrings
                                      .broadcastHistory
                                      .removeOneDialogMessage,
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: Text(
                                      AppStrings
                                          .broadcastHistory
                                          .removeOneDialogCancel,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: Text(
                                      AppStrings
                                          .broadcastHistory
                                          .removeOneDialogConfirm,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                          return confirmed == true;
                        },
                        onDismissed: (_) => unawaited(_removeOne(entry)),
                        child: _BroadcastHistoryTile(
                          entry: entry,
                          onTap: () => _showEntryDetail(entry),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.history, size: 48),
            const SizedBox(height: 12),
            Text(
              AppStrings.broadcastHistory.emptyTitle,
              key: const Key('broadcast-history-empty-title'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.broadcastHistory.emptyDescription,
              key: const Key('broadcast-history-empty-description'),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.broadcastHistory.privacyNote,
              key: const Key('broadcast-history-empty-privacy-note'),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BroadcastHistoryTile extends StatelessWidget {
  const _BroadcastHistoryTile({required this.entry, required this.onTap});

  final BroadcastHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String title = entry.programTitle?.trim().isNotEmpty == true
        ? entry.programTitle!
        : entry.lv;
    final String subtitle = AppStrings.broadcastHistory.tileSubtitle(
      lv: entry.lv,
      recordedAt: entry.recordedAt,
      totalComments: entry.totalComments,
      uniqueUserCount: entry.uniqueUserCount,
    );
    return ListTile(
      key: Key('broadcast-history-tile-${entry.lv}'),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _BroadcastHistoryDetailSheet extends StatelessWidget {
  const _BroadcastHistoryDetailSheet({
    required this.entry,
    required this.onOpenProgramPage,
  });

  final BroadcastHistoryEntry entry;
  final VoidCallback onOpenProgramPage;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.bar_chart, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.programTitle?.trim().isNotEmpty == true
                        ? entry.programTitle!
                        : entry.lv,
                    key: const Key('broadcast-history-detail-title'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DetailRow(
              key: const Key('broadcast-history-detail-lv'),
              label: AppStrings.broadcastHistory.detailLvLabel,
              value: entry.lv,
            ),
            _DetailRow(
              key: const Key('broadcast-history-detail-total'),
              label: AppStrings.broadcastHistory.detailTotalCommentsLabel,
              value: '${entry.totalComments}',
            ),
            _DetailRow(
              key: const Key('broadcast-history-detail-unique'),
              label: AppStrings.broadcastHistory.detailUniqueUsersLabel,
              value: '${entry.uniqueUserCount}',
            ),
            _DetailRow(
              key: const Key('broadcast-history-detail-duration'),
              label: AppStrings.broadcastHistory.detailDurationLabel,
              value: CommentLogStats.formatDuration(entry.duration),
            ),
            if (entry.peakMinuteLabel != null && entry.peakMinuteCount > 0)
              _DetailRow(
                key: const Key('broadcast-history-detail-peak'),
                label: AppStrings.broadcastHistory.detailPeakLabel,
                value: AppStrings.broadcastHistory.detailPeakValue(
                  label: entry.peakMinuteLabel!,
                  count: entry.peakMinuteCount,
                ),
              ),
            if (entry.peaks.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                AppStrings.broadcastHistory.detailHighlightTitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < entry.peaks.length; i++)
                Padding(
                  key: Key('broadcast-history-detail-highlight-$i'),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    AppStrings.broadcastHistory.detailHighlightLine(
                      index: i + 1,
                      label: entry.peaks[i].label,
                      count: entry.peaks[i].commentCount,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('broadcast-history-detail-open-program-page'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(AppStrings.broadcastHistory.openProgramPageButton),
                onPressed: onOpenProgramPage,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.broadcastHistory.privacyNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 14)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
