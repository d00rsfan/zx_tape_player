import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class ZxSettingsService extends SettingsService {
  static const _audioFilterPrefsKey = 'audioFilter';
  static const _zxModelPrefsKey = 'zxModel';

  AudioFilterType _audioFilter = SettingsService.defaultAudioFilter;
  ZxModel _zxModel = SettingsService.defaultZxModel;
  bool _loaded = false;
  final _filterChanges = StreamController<AudioFilterType>.broadcast();

  @override
  AudioFilterType get audioFilter => _audioFilter;

  @override
  ZxModel get zxModel => _zxModel;

  @override
  Stream<AudioFilterType> get filterChanges => _filterChanges.stream;

  @override
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _audioFilter =
        _parseAudioFilter(prefs.getString(_audioFilterPrefsKey)) ??
        SettingsService.defaultAudioFilter;
    _zxModel =
        _parseZxModel(prefs.getString(_zxModelPrefsKey)) ??
        SettingsService.defaultZxModel;
  }

  @override
  Future<void> setAudioFilter(AudioFilterType filter) async {
    if (_audioFilter == filter) return;
    _audioFilter = filter;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_audioFilterPrefsKey, filter.name);
    _filterChanges.add(filter);
  }

  @override
  Future<void> setZxModel(ZxModel model) async {
    if (_zxModel == model) return;
    _zxModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_zxModelPrefsKey, model.name);
  }

  @override
  Future<void> resetAudioFilterToDefault() =>
      setAudioFilter(SettingsService.defaultAudioFilter);

  @override
  Future<void> resetZxModelToDefault() =>
      setZxModel(SettingsService.defaultZxModel);

  AudioFilterType? _parseAudioFilter(String? name) {
    if (name == null) return null;
    for (final v in AudioFilterType.values) {
      if (v.name == name) return v;
    }
    return null;
  }

  ZxModel? _parseZxModel(String? name) {
    if (name == null) return null;
    for (final v in ZxModel.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
