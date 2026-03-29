import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/comment_log/comment_log_stats.dart';
import '../../domain/models/app_settings.dart';
import '../theme/app_theme.dart';

/// Bottom sheet that displays comment log statistics summary.
///
/// Shown when a connection ends (ENDED/STOPPED) and there are comments
/// to summarize.
class CommentLogStatsSheet extends StatelessWidget {
  const CommentLogStatsSheet({
    super.key,
    required this.stats,
    required this.themeMode,
    this.programTitle,
    this.lv,
  });

  final CommentLogStats stats;
  final AppThemeMode themeMode;
  final String? programTitle;
  final String? lv;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors themeColors = AppTheme.colorsFor(themeMode);

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.7,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          children: <Widget>[
            _buildHandle(themeColors),
            _buildTitle(context),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: <Widget>[
                  _StatRow(
                    key: const Key('stats-total-comments'),
                    label: '総コメント数',
                    value: '${stats.totalComments}',
                  ),
                  _StatRow(
                    key: const Key('stats-unique-users'),
                    label: 'ユニークユーザー数',
                    value: '${stats.uniqueUserCount}',
                  ),
                  _StatRow(
                    key: const Key('stats-duration'),
                    label: '配信時間',
                    value: CommentLogStats.formatDuration(stats.duration),
                  ),
                  if (stats.peakMinuteLabel != null &&
                      stats.peakMinuteCount > 0)
                    _StatRow(
                      key: const Key('stats-peak'),
                      label: 'ピーク時間帯',
                      value:
                          '${stats.peakMinuteLabel} (${stats.peakMinuteCount}コメント)',
                    ),
                  const SizedBox(height: 16),
                  _buildActions(context),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHandle(AppThemeColors themeColors) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: themeColors.subtleTextColor,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.bar_chart, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'コメント統計サマリ',
              key: Key('stats-sheet-title'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            key: const Key('stats-close-button'),
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '閉じる',
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final String shareText =
        stats.toShareText(programTitle: programTitle, lv: lv);

    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('stats-copy-button'),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('コピー'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: shareText));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(content: Text('コピーしました')),
                  );
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('stats-share-button'),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('共有'),
            onPressed: () async {
              await Share.share(shareText);
            },
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    super.key,
    required this.label,
    required this.value,
  });

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
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
