import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

import '../../domain/comment_log/comment_log_stats.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../theme/app_theme.dart';
import 'comment_frequency_chart.dart';

/// Bottom sheet that displays comment log statistics summary.
///
/// Shown when a connection ends (ENDED/STOPPED) and there are comments
/// to summarize.
///
/// This modal variant is still used in places that embed the sheet via
/// `showModalBottomSheet`. The in-screen non-modal variant is
/// [CommentLogStatsPanel].
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
    final List<HighlightPeak> peaks = highlightPickupEnabled
        ? CommentLogStats.detectPeaks(
            messages,
            commentsPerMinute: stats.commentsPerMinute,
            ngUserIds: ngUserIds,
          )
        : const <HighlightPeak>[];
    return DraggableScrollableSheet(
      initialChildSize: peaks.isNotEmpty ? 0.65 : 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return _StatsBody(
          stats: stats,
          themeMode: themeMode,
          programTitle: programTitle,
          lv: lv,
          peaks: peaks,
          onBarTapped: onBarTapped,
          onPeakTapped: onPeakTapped,
          scrollController: scrollController,
          showDragHandle: true,
          onClose: () => Navigator.of(context).pop(),
        );
      },
    );
  }
}

/// Non-modal, in-screen variant of the stats panel. Lives inside the
/// comment screen build tree and supports an expanded / minimized state
/// so accidental dismissal does not lose access to the summary.
class CommentLogStatsPanel extends StatelessWidget {
  const CommentLogStatsPanel({
    super.key,
    required this.stats,
    required this.themeMode,
    required this.expanded,
    this.programTitle,
    this.lv,
    this.highlightPickupEnabled = false,
    this.messages = const <AppMessage>[],
    this.ngUserIds = const <String>{},
    this.onBarTapped,
    this.onPeakTapped,
    this.onToggleExpanded,
  });

  // Visual geometry constants. Kept here (not at library level) so tests
  // or a future theming pass can override by subclassing if needed.
  // 48 matches the Material Design minimum touch target.
  static const double _minimizedBarHeight = 48;
  static const double _expandedHeightRatio = 0.55;
  static const double _expandedMinHeight = 240;

  final CommentLogStats stats;
  final AppThemeMode themeMode;

  /// When true the full stats content is shown. When false only a
  /// compact header bar is rendered; tapping it (or the restore icon)
  /// is expected to flip this back to true via [onToggleExpanded].
  final bool expanded;

  final String? programTitle;
  final String? lv;
  final bool highlightPickupEnabled;
  final List<AppMessage> messages;
  final Set<String> ngUserIds;
  final void Function(int minuteOffset)? onBarTapped;
  final void Function(int minuteOffset)? onPeakTapped;
  final VoidCallback? onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors themeColors = AppTheme.colorsFor(themeMode);

    if (!expanded) {
      return Material(
        key: const Key('stats-panel-minimized'),
        color: themeColors.statusBarBackground,
        elevation: 4,
        child: InkWell(
          onTap: onToggleExpanded,
          child: Semantics(
            button: true,
            label: '統計を開く',
            child: SizedBox(
              height: _minimizedBarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.bar_chart, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'コメント統計サマリ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('stats-panel-expand-button'),
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: onToggleExpanded,
                      tooltip: '統計を開く',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final List<HighlightPeak> peaks = highlightPickupEnabled
        ? CommentLogStats.detectPeaks(
            messages,
            commentsPerMinute: stats.commentsPerMinute,
            ngUserIds: ngUserIds,
          )
        : const <HighlightPeak>[];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height;
        final double height = (available * _expandedHeightRatio).clamp(
          _expandedMinHeight,
          available,
        );
        return Material(
          key: const Key('stats-panel-expanded'),
          color: Theme.of(context).scaffoldBackgroundColor,
          elevation: 8,
          child: SizedBox(
            height: height,
            child: _StatsBody(
              stats: stats,
              themeMode: themeMode,
              programTitle: programTitle,
              lv: lv,
              peaks: peaks,
              onBarTapped: onBarTapped,
              onPeakTapped: onPeakTapped,
              showDragHandle: false,
              onClose: onToggleExpanded,
              closeIcon: Icons.keyboard_arrow_down,
              closeTooltip: '最小化',
            ),
          ),
        );
      },
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({
    required this.stats,
    required this.themeMode,
    required this.programTitle,
    required this.lv,
    required this.peaks,
    required this.onBarTapped,
    required this.onPeakTapped,
    required this.showDragHandle,
    required this.onClose,
    this.scrollController,
    this.closeIcon = Icons.close,
    this.closeTooltip = '閉じる',
  });

  final CommentLogStats stats;
  final AppThemeMode themeMode;
  final String? programTitle;
  final String? lv;

  /// Pre-computed peaks. The caller (`CommentLogStatsSheet` /
  /// `CommentLogStatsPanel`) owns peak detection so it runs once per
  /// build even when both the container and the body need the result.
  final List<HighlightPeak> peaks;
  final void Function(int minuteOffset)? onBarTapped;
  final void Function(int minuteOffset)? onPeakTapped;
  final ScrollController? scrollController;
  final bool showDragHandle;
  final VoidCallback? onClose;
  final IconData closeIcon;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors themeColors = AppTheme.colorsFor(themeMode);
    final Set<int> peakMinutes = peaks
        .map((HighlightPeak p) => p.minuteOffset)
        .toSet();

    return Column(
      children: <Widget>[
        if (showDragHandle) _buildHandle(themeColors),
        _buildTitle(context),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              if (stats.peakMinuteLabel != null && stats.peakMinuteCount > 0)
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
              if (peaks.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20),
                const Text(
                  '放送の盛り上がり',
                  key: Key('highlight-pickup-title'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
          if (onClose != null)
            IconButton(
              key: const Key('stats-close-button'),
              icon: Icon(closeIcon),
              onPressed: onClose,
              tooltip: closeTooltip,
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
              await SharePlus.instance.share(ShareParams(text: shareText));
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
