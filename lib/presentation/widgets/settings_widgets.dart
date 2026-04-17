import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';

/// Saves [settings] to [store] with standardized error reporting.
Future<void> saveSettingsToStore(
  SettingsStore store,
  AppSettings settings,
) async {
  try {
    await store.save(settings);
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'settings',
        context: ErrorDescription('while saving settings'),
      ),
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class SettingsIntSliderField extends StatelessWidget {
  const SettingsIntSliderField({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
    this.suffix = '',
    this.sweetSpotMin,
    this.sweetSpotMax,
    this.sweetSpotLabel,
  });

  final String label;
  final int min;
  final int max;
  final int divisions;
  final int value;
  final ValueChanged<int> onChanged;
  final String suffix;
  final int? sweetSpotMin;
  final int? sweetSpotMax;
  final String? sweetSpotLabel;

  @override
  Widget build(BuildContext context) {
    final bool hasSweetSpot = sweetSpotMin != null && sweetSpotMax != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label),
            const Spacer(),
            Text(value == -1 ? '-1 (既定)' : '$value$suffix'),
          ],
        ),
        if (hasSweetSpot)
          _SweetSpotSlider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            suffix: suffix,
            sweetSpotMin: sweetSpotMin!,
            sweetSpotMax: sweetSpotMax!,
            sweetSpotLabel: sweetSpotLabel,
            onChanged: onChanged,
          )
        else
          Slider(
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            value: value.toDouble(),
            semanticFormatterCallback: suffix.isNotEmpty
                ? (double v) => '${v.round()}$suffix'
                : null,
            onChanged: (double next) {
              onChanged(next.round());
            },
          ),
      ],
    );
  }
}

class _SweetSpotSlider extends StatelessWidget {
  const _SweetSpotSlider({
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.suffix,
    required this.sweetSpotMin,
    required this.sweetSpotMax,
    this.sweetSpotLabel,
    required this.onChanged,
  });

  final int min;
  final int max;
  final int divisions;
  final int value;
  final String suffix;
  final int sweetSpotMin;
  final int sweetSpotMax;
  final String? sweetSpotLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double sliderPadding = 24.0;
        final double trackWidth = constraints.maxWidth - sliderPadding * 2;
        final double range = (max - min).toDouble();
        final double leftFraction = (sweetSpotMin - min) / range;
        final double rightFraction = (sweetSpotMax - min) / range;
        final double left = sliderPadding + trackWidth * leftFraction;
        final double width = trackWidth * (rightFraction - leftFraction);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                Positioned(
                  left: left,
                  top: 16,
                  width: width,
                  height: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Slider(
                  min: min.toDouble(),
                  max: max.toDouble(),
                  divisions: divisions,
                  value: value.toDouble(),
                  semanticFormatterCallback: suffix.isNotEmpty
                      ? (double v) => '${v.round()}$suffix'
                      : null,
                  onChanged: (double next) {
                    onChanged(next.round());
                  },
                ),
              ],
            ),
            if (sweetSpotLabel != null)
              Padding(
                padding: EdgeInsets.only(
                  left: left,
                  right: (constraints.maxWidth - left - width).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: SizedBox(
                  width: width,
                  child: Text(
                    sweetSpotLabel!,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SettingsDoubleSliderField extends StatelessWidget {
  const SettingsDoubleSliderField({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label),
            const Spacer(),
            Text(value.toStringAsFixed(2)),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value,
          semanticFormatterCallback: (double v) =>
              '$label ${v.toStringAsFixed(2)}',
          onChanged: (double next) {
            onChanged(double.parse(next.toStringAsFixed(2)));
          },
        ),
      ],
    );
  }
}
