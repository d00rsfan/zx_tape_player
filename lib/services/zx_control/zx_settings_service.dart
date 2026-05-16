import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class ZxSettingsService extends SettingsService {
  static const _prefsKey = 'audioFilter';

  AudioFilterType _audioFilter = SettingsService.defaultAudioFilter;
  bool _loaded = false;
  final _filterChanges = StreamController<AudioFilterType>.broadcast();

  @override
  AudioFilterType get audioFilter => _audioFilter;

  @override
  Stream<AudioFilterType> get filterChanges => _filterChanges.stream;

  @override
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefsKey);
    _audioFilter = _parse(name) ?? SettingsService.defaultAudioFilter;
  }

  @override
  Future<void> setAudioFilter(AudioFilterType filter) async {
    if (_audioFilter == filter) return;
    _audioFilter = filter;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, filter.name);
    _filterChanges.add(filter);
  }

  @override
  Future<void> resetAudioFilterToDefault() =>
      setAudioFilter(SettingsService.defaultAudioFilter);

  AudioFilterType? _parse(String? name) {
    if (name == null) return null;
    for (final v in AudioFilterType.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
