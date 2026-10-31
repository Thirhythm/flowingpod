import 'dart:math' as math;

import 'package:flowingpod/core/models/equalizer_capabilities.dart';
import 'package:flowingpod/core/models/equalizer_curve.dart';
import 'package:flowingpod/core/models/equalizer_preset.dart';
import 'package:flowingpod/core/utils/formatters.dart';
import 'package:flowingpod/state/effects_controller.dart';
import 'package:flowingpod/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loudness enhancer gain offered by the UI, in decibels.
const double _maxLoudnessGain = 10.0;

/// 均衡器: equalizer presets, per-band gains and loudness enhancer.
class EffectsPage extends ConsumerWidget {
  const EffectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(effectsControllerProvider);
    final controller = ref.read(effectsControllerProvider.notifier);
    final settings = state.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('均衡器 (BETA)')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.equalizer_rounded),
            title: const Text('启用均衡器'),
            value: settings.equalizerEnabled,
            onChanged: controller.setEqualizerEnabled,
          ),
          const Divider(height: 1),
          const SectionHeader(title: '预设', action: null),
          _PresetPicker(
            selectedId: settings.presetId,
            enabled: settings.equalizerEnabled,
            onSelected: controller.selectPreset,
          ),
          SectionHeader(
            title: '频段（${state.bandLayout.bands.length} 段）',
            action: null,
          ),
          _ResponseCurve(
            capabilities: state.bandLayout,
            curve: settings.curve,
            enabled: settings.equalizerEnabled,
          ),
          _BandEditor(
            capabilities: state.bandLayout,
            gains: state.bandGains,
            enabled: settings.equalizerEnabled,
            onChanged: controller.setBandGain,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('自动预增益'),
            subtitle: Text(
              settings.headroomEnabled
                  ? '按曲线峰值自动衰减（当前 ${Formatters.decibels(state.preampDecibels)}），避免强增益造成失真'
                  : '已关闭，提升频段时可能出现削波失真',
            ),
            value: settings.headroomEnabled,
            onChanged: controller.setHeadroomEnabled,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: const Text('响度增强'),
            value: settings.loudnessEnabled,
            onChanged: controller.setLoudnessEnabled,
          ),
          _LoudnessSlider(
            gain: settings.loudnessGain.clamp(0.0, _maxLoudnessGain).toDouble(),
            enabled: settings.loudnessEnabled,
            onChanged: controller.setLoudnessGain,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.restart_alt_rounded),
            title: const Text('恢复默认'),
            onTap: controller.reset,
          ),
        ],
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({
    required this.selectedId,
    required this.enabled,
    required this.onSelected,
  });

  final String selectedId;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final presets = [...EqualizerPreset.values, EqualizerPreset.custom];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in presets)
            ChoiceChip(
              label: Text(preset.label),
              selected: preset.id == selectedId,
              // `自定义` only reflects hand-edited bands, so it is never tappable.
              onSelected: !enabled || preset.isCustom
                  ? null
                  : (_) => onSelected(preset.id),
            ),
        ],
      ),
    );
  }
}

/// Draws the response the equalizer applies, with a marker on every band.
class _ResponseCurve extends StatelessWidget {
  const _ResponseCurve({
    required this.capabilities,
    required this.curve,
    required this.enabled,
  });

  final EqualizerCapabilities capabilities;
  final EqualizerCurve curve;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.4,
        child: Semantics(
          label: '频响曲线',
          child: SizedBox(
            height: 112,
            width: double.infinity,
            child: CustomPaint(
              painter: _ResponseCurvePainter(
                capabilities: capabilities,
                curve: curve,
                lineColor: scheme.primary,
                fillColor: scheme.primary.withValues(alpha: 0.14),
                gridColor: scheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponseCurvePainter extends CustomPainter {
  const _ResponseCurvePainter({
    required this.capabilities,
    required this.curve,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final EqualizerCapabilities capabilities;
  final EqualizerCurve curve;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  /// Painted frequency bounds; bands outside them are drawn at the edges.
  static const double _minFrequency = 20;
  static const double _maxFrequency = 20000;

  /// How many points the curve is sampled at between the bounds.
  static const int _samples = 128;

  @override
  void paint(Canvas canvas, Size size) {
    final bands = capabilities.bands;
    final span = capabilities.maxDecibels - capabilities.minDecibels;
    if (size.isEmpty || bands.isEmpty || span <= 0) return;

    double x(double hertz) =>
        size.width *
        (math.log(hertz.clamp(_minFrequency, _maxFrequency) / _minFrequency) /
            math.log(_maxFrequency / _minFrequency));
    double y(double decibels) =>
        size.height *
        (1 -
            (decibels.clamp(
                      capabilities.minDecibels,
                      capabilities.maxDecibels,
                    ) -
                    capabilities.minDecibels) /
                span);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    // Guide line per band, then the neutral 0 dB line on top of them.
    for (final band in bands) {
      final bandX = x(band.centerFrequency);
      canvas.drawLine(Offset(bandX, 0), Offset(bandX, size.height), gridPaint);
    }
    final zeroY = y(0);
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), gridPaint);

    final curvePath = Path();
    final fillPath = Path();
    for (var i = 0; i < _samples; i++) {
      final hertz =
          _minFrequency *
          math.pow(_maxFrequency / _minFrequency, i / (_samples - 1));
      final point = Offset(x(hertz), y(curve.gainAt(hertz)));
      if (i == 0) {
        curvePath.moveTo(point.dx, point.dy);
        fillPath
          ..moveTo(point.dx, zeroY)
          ..lineTo(point.dx, point.dy);
      } else {
        curvePath.lineTo(point.dx, point.dy);
        fillPath.lineTo(point.dx, point.dy);
      }
    }
    fillPath
      ..lineTo(size.width, zeroY)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dotPaint = Paint()..color = lineColor;
    for (final band in bands) {
      canvas.drawCircle(
        Offset(x(band.centerFrequency), y(curve.gainAt(band.centerFrequency))),
        3,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ResponseCurvePainter oldDelegate) =>
      oldDelegate.curve != curve ||
      oldDelegate.capabilities != capabilities ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.gridColor != gridColor;
}

class _BandEditor extends StatelessWidget {
  const _BandEditor({
    required this.capabilities,
    required this.gains,
    required this.enabled,
    required this.onChanged,
  });

  final EqualizerCapabilities capabilities;
  final List<double> gains;
  final bool enabled;
  final void Function(int index, double gain) onChanged;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    // Five bands spread over the full width; a ten-band layout gets a
    // scrollable editor so each slider keeps a usable size.
    const minBandWidth = 44.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bandWidth = math.max(
          minBandWidth,
          constraints.maxWidth / capabilities.bands.length,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: bandWidth * capabilities.bands.length,
            height: 240,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, band) in capabilities.bands.indexed)
                  SizedBox(
                    width: bandWidth,
                    child: Column(
                      children: [
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              min: capabilities.minDecibels,
                              max: capabilities.maxDecibels,
                              // Half-decibel steps keep the labels readable.
                              divisions:
                                  ((capabilities.maxDecibels -
                                              capabilities.minDecibels) *
                                          2)
                                      .round(),
                              label: Formatters.decibels(gains[index]),
                              value: gains[index],
                              onChanged: enabled
                                  ? (gain) => onChanged(index, gain)
                                  : null,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            Formatters.frequency(band.centerFrequency),
                            style: labelStyle,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            Formatters.decibels(gains[index]),
                            style: labelStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoudnessSlider extends StatelessWidget {
  const _LoudnessSlider({
    required this.gain,
    required this.enabled,
    required this.onChanged,
  });

  final double gain;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('增益'),
          Expanded(
            child: Slider(
              min: 0,
              max: _maxLoudnessGain,
              divisions: (_maxLoudnessGain * 2).round(),
              label: Formatters.decibels(gain),
              value: gain,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              Formatters.decibels(gain),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
