import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A bar chart that visualises per-minute comment frequency.
///
/// Each bar represents one minute offset from broadcast start. Tapping a bar
/// invokes [onBarTapped] with the minute offset so the caller can scroll the
/// comment list to that time range.
class CommentFrequencyChart extends StatelessWidget {
  const CommentFrequencyChart({
    super.key,
    required this.commentsPerMinute,
    this.onBarTapped,
    this.barColor = const Color(0xFF1976D2),
    this.peakBarColor = const Color(0xFFFF5722),
    this.peakMinutes = const <int>{},
    this.height = 120,
  });

  /// Comments per minute. Key = minute offset, value = count.
  final Map<int, int> commentsPerMinute;

  /// Called when a bar is tapped with the minute offset.
  final void Function(int minuteOffset)? onBarTapped;

  /// Default bar color.
  final Color barColor;

  /// Bar color for peak minutes.
  final Color peakBarColor;

  /// Set of minute offsets that are peak minutes (highlighted differently).
  final Set<int> peakMinutes;

  /// Chart height.
  final double height;

  @override
  Widget build(BuildContext context) {
    if (commentsPerMinute.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'データなし',
            style: TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final int maxCount = commentsPerMinute.values.fold<int>(
      0,
      (int a, int b) => a > b ? a : b,
    );
    final int totalMinutes = commentsPerMinute.keys.fold<int>(
      0,
      (int a, int b) => a > b ? a : b,
    );

    return Semantics(
      label: 'コメント頻度グラフ: ${totalMinutes + 1}分間、最大$maxCountコメント/分',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return _BarChartBody(
                  commentsPerMinute: commentsPerMinute,
                  onBarTapped: onBarTapped,
                  barColor: barColor,
                  peakBarColor: peakBarColor,
                  peakMinutes: peakMinutes,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                );
              },
            ),
          ),
          _buildTimeAxis(),
        ],
      ),
    );
  }

  Widget _buildTimeAxis() {
    final int maxMinute = commentsPerMinute.keys.fold<int>(
      0,
      (int a, int b) => a > b ? a : b,
    );

    final List<String> labels = <String>[];
    if (maxMinute <= 60) {
      for (int m = 0; m <= maxMinute; m += 15) {
        labels.add('$m');
      }
      // Always show the last label if not already included.
      if (maxMinute % 15 != 0) {
        labels.add('$maxMinute');
      }
    } else {
      final int step = (maxMinute / 4).ceil();
      for (int m = 0; m <= maxMinute; m += step) {
        labels.add('$m');
      }
      if (labels.length < 5 && maxMinute > 0) {
        labels.add('$maxMinute');
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          for (final String label in labels)
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF757575)),
            ),
          const Text(
            '(分)',
            style: TextStyle(fontSize: 10, color: Color(0xFF757575)),
          ),
        ],
      ),
    );
  }
}

class _BarChartBody extends StatelessWidget {
  const _BarChartBody({
    required this.commentsPerMinute,
    required this.onBarTapped,
    required this.barColor,
    required this.peakBarColor,
    required this.peakMinutes,
    required this.width,
    required this.height,
  });

  final Map<int, int> commentsPerMinute;
  final void Function(int minuteOffset)? onBarTapped;
  final Color barColor;
  final Color peakBarColor;
  final Set<int> peakMinutes;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final int maxMinute = commentsPerMinute.keys.fold<int>(
      0,
      (int a, int b) => a > b ? a : b,
    );
    final int maxCount = commentsPerMinute.values.fold<int>(
      0,
      (int a, int b) => a > b ? a : b,
    );
    final int totalBars = maxMinute + 1;

    if (totalBars <= 0 || maxCount <= 0) {
      return const SizedBox.shrink();
    }

    // Calculate bar width, ensuring minimum touch target.
    final double barWidth = math.max(2, width / totalBars - 1);
    final double gap =
        totalBars > 1 ? (width - barWidth * totalBars) / (totalBars - 1) : 0;

    return GestureDetector(
      onTapUp: onBarTapped == null
          ? null
          : (TapUpDetails details) {
              final double dx = details.localPosition.dx;
              final double effectiveBarWidth = barWidth + gap;
              final int index = (dx / effectiveBarWidth).floor().clamp(
                    0,
                    totalBars - 1,
                  );
              onBarTapped!.call(index);
            },
      child: CustomPaint(
        size: Size(width, height),
        painter: _BarChartPainter(
          commentsPerMinute: commentsPerMinute,
          maxMinute: maxMinute,
          maxCount: maxCount,
          barColor: barColor,
          peakBarColor: peakBarColor,
          peakMinutes: peakMinutes,
          barWidth: barWidth,
          gap: gap,
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.commentsPerMinute,
    required this.maxMinute,
    required this.maxCount,
    required this.barColor,
    required this.peakBarColor,
    required this.peakMinutes,
    required this.barWidth,
    required this.gap,
  });

  final Map<int, int> commentsPerMinute;
  final int maxMinute;
  final int maxCount;
  final Color barColor;
  final Color peakBarColor;
  final Set<int> peakMinutes;
  final double barWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint normalPaint = Paint()..color = barColor;
    final Paint peakPaint = Paint()..color = peakBarColor;

    for (int minute = 0; minute <= maxMinute; minute++) {
      final int count = commentsPerMinute[minute] ?? 0;
      if (count == 0) {
        continue;
      }
      final double barHeight = (count / maxCount) * size.height;
      final double x = minute * (barWidth + gap);
      final double y = size.height - barHeight;

      final Paint paint =
          peakMinutes.contains(minute) ? peakPaint : normalPaint;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          topLeft: const Radius.circular(1),
          topRight: const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.commentsPerMinute != commentsPerMinute ||
        oldDelegate.maxCount != maxCount ||
        oldDelegate.barColor != barColor ||
        oldDelegate.peakBarColor != peakBarColor;
  }
}
