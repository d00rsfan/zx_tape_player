import 'package:flutter/material.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/utils/extensions.dart';

class RateControlSheetShell extends StatelessWidget {
  const RateControlSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.explanation,
  });

  final String title;
  final String? explanation;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: HexColor('#3B4E63'),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('rate_control_sheet_scroll_view'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8.0),
            Container(
              width: 40.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: HexColor('#546B7F'),
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (explanation != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 12.0),
                child: Text(
                  explanation!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: HexColor('#D8DCE0'), fontSize: 12.0),
                ),
              ),
            child,
          ],
        ),
      ),
    ),
  );
}

class PlaybackSpeedSheet extends StatelessWidget {
  const PlaybackSpeedSheet({
    super.key,
    required this.title,
    required this.divisions,
    required this.min,
    required this.max,
    required this.stream,
    required this.onChanged,
    this.valueSuffix = '',
    this.decimals = 1,
    this.presets,
  });

  final String title;
  final int divisions;
  final double min;
  final double max;
  final String valueSuffix;
  final int decimals;
  final List<double>? presets;
  final Stream<double> stream;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => RateControlSheetShell(
    title: title,
    child: StreamBuilder<double>(
      stream: stream,
      builder: (context, snapshot) {
        final value = snapshot.data ?? 1.0;
        final step = (max - min) / divisions;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                '${value.toStringAsFixed(decimals)}$valueSuffix',
                style: const TextStyle(
                  wordSpacing: 0.5,
                  fontSize: 24.0,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: SliderTheme(
                data: SliderThemeData(
                  activeTickMarkColor: Colors.transparent,
                  activeTrackColor: HexColor('#546B7F'),
                  inactiveTickMarkColor: Colors.transparent,
                  inactiveTrackColor: HexColor('#546B7F'),
                  thumbColor: Colors.white,
                ),
                child: Row(
                  children: [
                    _stepButton(
                      key: const ValueKey('speed_decrease_button'),
                      icon: Icons.remove_rounded,
                      onPressed: value > min
                          ? () => onChanged((value - step).clamp(min, max))
                          : null,
                    ),
                    Expanded(
                      child: Slider(
                        divisions: divisions,
                        min: min,
                        max: max,
                        value: value.clamp(min, max),
                        onChanged: onChanged,
                      ),
                    ),
                    _stepButton(
                      key: const ValueKey('speed_increase_button'),
                      icon: Icons.add_rounded,
                      onPressed: value < max
                          ? () => onChanged((value + step).clamp(min, max))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            if (presets != null) ...[
              const SizedBox(height: 8.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    for (final preset in presets!)
                      RatePresetButton(
                        label: preset.toStringAsFixed(decimals),
                        onPressed: () => onChanged(preset),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16.0),
          ],
        );
      },
    ),
  );

  static Widget _stepButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => IconButton(
    key: key,
    style: IconButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: HexColor('#546B7F'),
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    icon: Icon(icon),
    onPressed: onPressed,
  );
}

class RatePresetButton extends StatelessWidget {
  const RatePresetButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      backgroundColor: selected ? Colors.white : HexColor('#546B7F'),
      foregroundColor: selected ? HexColor('#28384C') : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class SnapshotTurboProfileSheet extends StatelessWidget {
  const SnapshotTurboProfileSheet({
    super.key,
    required this.title,
    required this.explanation,
    required this.activeProfile,
    required this.invertPolarity,
    required this.invertPolarityLabel,
    required this.sampleRate,
    required this.sampleRateLabel,
    required this.onSelected,
    required this.onPolarityChanged,
    required this.onSampleRateChanged,
  });

  final String title;
  final String explanation;
  final SnapshotTurboProfile activeProfile;
  final bool invertPolarity;
  final String invertPolarityLabel;
  final SnapshotAudioSampleRate sampleRate;
  final String sampleRateLabel;
  final ValueChanged<SnapshotTurboProfile> onSelected;
  final ValueChanged<bool> onPolarityChanged;
  final ValueChanged<SnapshotAudioSampleRate> onSampleRateChanged;

  @override
  Widget build(BuildContext context) => RateControlSheetShell(
    title: title,
    explanation: explanation,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              for (final profile in SnapshotTurboProfiles.values)
                Semantics(
                  key: ValueKey('snapshot_turbo_profile_${profile.id}'),
                  label: profile.label,
                  button: true,
                  selected: profile == activeProfile,
                  child: RatePresetButton(
                    label: profile.label,
                    selected: profile == activeProfile,
                    onPressed: () => onSelected(profile),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              sampleRateLabel,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 8.0),
        SegmentedButton<SnapshotAudioSampleRate>(
          key: const ValueKey('snapshot_sample_rate'),
          segments: [
            for (final rate in SnapshotAudioSampleRate.values)
              ButtonSegment(value: rate, label: Text(rate.label)),
          ],
          selected: {sampleRate},
          showSelectedIcon: false,
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? HexColor('#28384C')
                  : Colors.white,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.transparent,
            ),
            side: const WidgetStatePropertyAll(BorderSide(color: Colors.white)),
          ),
          onSelectionChanged: (selection) {
            final selected = selection.single;
            if (selected != sampleRate) onSampleRateChanged(selected);
          },
        ),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            key: const ValueKey('snapshot_invert_polarity'),
            value: invertPolarity,
            onChanged: (value) {
              if (value != null) onPolarityChanged(value);
            },
            title: Text(
              invertPolarityLabel,
              style: const TextStyle(color: Colors.white),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          ),
        ),
        const SizedBox(height: 4.0),
      ],
    ),
  );
}
