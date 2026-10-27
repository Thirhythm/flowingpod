import 'package:flowingpod/core/models/equalizer_capabilities.dart';
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
          const SectionHeader(title: '频段', action: null),
          _BandEditor(
            capabilities: state.bandLayout,
            gains: state.bandGains,
            engineReady: state.engineReady,
            enabled: settings.equalizerEnabled,
            onChanged: controller.setBandGain,
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

class _BandEditor extends StatelessWidget {
  const _BandEditor({
    required this.capabilities,
    required this.gains,
    required this.engineReady,
    required this.enabled,
    required this.onChanged,
  });

  final EqualizerCapabilities capabilities;
  final List<double> gains;

  /// Whether [capabilities] comes from the engine instead of the reference
  /// layout shown before the engine reports anything.
  final bool engineReady;
  final bool enabled;
  final void Function(int index, double gain) onChanged;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      children: [
        SizedBox(
          height: 240,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, band) in capabilities.bands.indexed)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            min: capabilities.minDecibels,
                            max: capabilities.maxDecibels,
                            value: gains[index],
                            onChanged: enabled
                                ? (gain) => onChanged(index, gain)
                                : null,
                          ),
                        ),
                      ),
                      Text(
                        Formatters.frequency(band.centerFrequency),
                        style: labelStyle,
                      ),
                      Text(
                        Formatters.decibels(gains[index]),
                        style: labelStyle,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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
