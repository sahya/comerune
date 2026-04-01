import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/comment_log/comment_log_stats.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../theme/app_theme.dart';
import 'comment_frequency_chart.dart';

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
    this.highlightPickupEnabled = false,
    this.messages = const <AppMessage>[],
    this.ngUserIds = const <String>{},
    this.onBarTapped,
    this.onPeakTapped,
  });

  final CommentLogStats stats;
  final AppThemeMode themeMode;
  final String? programTitle;
  final String? lv;
  final bool highlightPickupEnabled;
  final List<AppMessage> messages;
  final Set<String> ngUserIds;

  /// Called when a bar in the frequency chart is tapped.
  final void Function(int minuteOffset)? onBarTapped;

  /// Called when a peak section is tapped.
  final void Function(int minuteOffset)? onPeakTapped;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors themeColors = AppTheme.colorsFor(themeMode);
    final List<HighlightPeak> peaks = highlightPickupEnabled
        ? CommentLogStats.detectPeaks(
            messages,
            commentsPerMinute: stats.commentsPerMinute,
            ngUserIds: ngUserIds,
          )
        : const <HighlightPeak>[];
    final Set<int> peakMinutes = peaks
        .map((HighlightPeak p) => p.minuteOffset)
        .toSet();

    return DraggableScrollableSheet(
      initialChildSize: highlightPickupEnabled && peaks.isNotEmpty ? 0.65 : 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                  if (stats.commentsPerMinute.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    const Text(
                      'コメント頻度',
                      key: Key('frequency-chart-title'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CommentFrequencyChart(
                      key: const Key('frequency-chart'),
                      commentsPerMinute: stats.commentsPerMinute,
                      onBarTapped: onBarTapped,
                      peakMinutes: peakMinutes,
                      barColor: themeColors.statusConnected,
                      peakBarColor: themeColors.ngUserActiveColor,
                    ),
                  ],
                  if (highlightPickupEnabled && peaks.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    const Text(
                      '放送の盛り上がり',
                      key: Key('highlight-pickup-title'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < peaks.length; i++)
                      _HighlightPeakCard(
                        key: Key('highlight-peak-$i'),
                        peak: peaks[i],
                        index: i + 1,
                        onTap: onPeakTapped,
                      ),
                  ],
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
    final String shareText = stats.toShareText(
      programTitle: programTitle,
      lv: lv,
    );

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
                  ..showSnackBar(const SnackBar(content: Text('コピーしました')));
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
  const _StatRow({super.key, required this.label, required this.value});

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

class _HighlightPeakCard extends StatelessWidget {
  const _HighlightPeakCard({
    super.key,
    required this.peak,
    required this.index,
    this.onTap,
  });

  final HighlightPeak peak;
  final int index;
  final void Function(int minuteOffset)? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap != null ? () => onTap!.call(peak.minuteOffset) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text('\u{1F525}', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(
                    'ピーク\u{2460}'.replaceFirst(
                      '\u{2460}',
                      String.fromCharCode(0x2460 + index - 1),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${peak.label} (${peak.commentCount}コメント/分)',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              if (peak.representativeComments.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                for (final AppMessage msg in peak.representativeComments)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, bottom: 2),
                    child: Text(
                      '${msg.userId ?? ""}: ${msg.content}',
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
