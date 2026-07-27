import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/ui/search_screen.dart';
import 'package:zx_tape_player/utils/extensions.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  static const routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = getIt<SettingsService>();
  final _volume = getIt<VolumeControlService>();

  static const _modelOptions = <_SettingsOption<ZxModel>>[
    _SettingsOption(
      value: ZxModel.zxSpectrum,
      labelKey: 'settings_model_zx_spectrum',
      descKey: 'settings_model_zx_spectrum_desc',
    ),
    _SettingsOption(
      value: ZxModel.zx81,
      labelKey: 'settings_model_zx81',
      descKey: 'settings_model_zx81_desc',
    ),
    _SettingsOption(
      value: ZxModel.zx80,
      labelKey: 'settings_model_zx80',
      descKey: 'settings_model_zx80_desc',
    ),
  ];

  static const _filterOptions = <_SettingsOption<AudioFilterType>>[
    _SettingsOption(
      value: AudioFilterType.bassBoost,
      labelKey: 'settings_filter_bass_boost',
      descKey: 'settings_filter_bass_boost_desc',
    ),
    _SettingsOption(
      value: AudioFilterType.none,
      labelKey: 'settings_filter_none',
      descKey: 'settings_filter_none_desc',
    ),
    _SettingsOption(
      value: AudioFilterType.sine,
      labelKey: 'settings_filter_sine',
      descKey: 'settings_filter_sine_desc',
    ),
    _SettingsOption(
      value: AudioFilterType.tapir,
      labelKey: 'settings_filter_tapir',
      descKey: 'settings_filter_tapir_desc',
    ),
  ];

  Future<void> _onModelChanged(ZxModel? value) async {
    if (value == null || value == _settings.zxModel) return;
    await _settings.setZxModel(value);
    if (!mounted) return;
    _navigateToEmptySearch();
  }

  void _navigateToEmptySearch() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      SearchScreen.routeName,
      (route) => route.isFirst,
      arguments: '',
    );
  }

  Future<void> _onFilterChanged(AudioFilterType? value) async {
    if (value == null) return;
    await _settings.setAudioFilter(value);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onReset() async {
    final modelChanged = _settings.zxModel != SettingsService.defaultZxModel;
    await _settings.resetZxModelToDefault();
    await _settings.resetAudioFilterToDefault();
    await _volume.resetToDefault();
    if (!mounted) return;
    if (modelChanged) {
      _navigateToEmptySearch();
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(tr('settings_reset_done'))));
  }

  @override
  Widget build(BuildContext context) {
    final currentModel = _settings.zxModel;
    final currentFilter = _settings.audioFilter;
    return Scaffold(
      backgroundColor: HexColor('#172434'),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_outlined,
            color: Colors.white,
            size: 16,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          tr('settings_title'),
          style: const TextStyle(color: Colors.white, letterSpacing: 0.1),
        ),
        titleSpacing: 0.0,
        toolbarHeight: 60.0,
        backgroundColor: HexColor('#28384C'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                tr('settings_model_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            RadioGroup<ZxModel>(
              groupValue: currentModel,
              onChanged: _onModelChanged,
              child: Column(
                children: _modelOptions
                    .map(
                      (o) => _SettingsOptionTile(
                        option: o,
                        groupValue: currentModel,
                        onChanged: _onModelChanged,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 24.0),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                tr('settings_audio_filter_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            RadioGroup<AudioFilterType>(
              groupValue: currentFilter,
              onChanged: _onFilterChanged,
              child: Column(
                children: _filterOptions
                    .map(
                      (o) => _SettingsOptionTile(
                        option: o,
                        groupValue: currentFilter,
                        onChanged: _onFilterChanged,
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 24.0),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _onReset,
                icon: const Icon(
                  Icons.restart_alt_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  tr('settings_reset_default'),
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HexColor('#3B4E63'),
                  padding: const EdgeInsets.symmetric(vertical: 14.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsOption<T> {
  const _SettingsOption({
    required this.value,
    required this.labelKey,
    required this.descKey,
  });

  final T value;
  final String labelKey;
  final String descKey;
}

class _SettingsOptionTile<T> extends StatelessWidget {
  const _SettingsOptionTile({
    required this.option,
    required this.groupValue,
    required this.onChanged,
  });

  final _SettingsOption<T> option;
  final T groupValue;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = option.value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: () => onChanged(option.value),
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: HexColor('#3B4E63'),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<T>(
                value: option.value,
                fillColor: WidgetStateProperty.all(Colors.white),
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(option.labelKey),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      tr(option.descKey),
                      style: TextStyle(
                        color: HexColor('#B1B8C1'),
                        fontSize: 12.0,
                        letterSpacing: 0.2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
