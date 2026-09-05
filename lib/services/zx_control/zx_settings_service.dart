import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class ZxSettingsService extends SettingsService {
  static const _audioFilterPrefsKey = 'audioFilter';
  static const _zxModelPrefsKey = 'zxModel';
  static const _audioSignalSettingsPrefsKey = 'audioSignalSettings';
  static const _legacySignalSettingsPrefsKey = 'snapshotSignalSettings';

  AudioFilterType _audioFilter = SettingsService.defaultAudioFilter;
  ZxModel _zxModel = SettingsService.defaultZxModel;
  AudioSignalSettings _audioSignalSettings =
      SettingsService.defaultAudioSignalSettings;
  bool _loaded = false;
  final _filterChanges = StreamController<AudioFilterType>.broadcast();
  final _signalChanges = StreamController<AudioSignalSettings>.broadcast();

  @override
  AudioFilterType get audioFilter => _audioFilter;

  @override
  ZxModel get zxModel => _zxModel;

  @override
  AudioSignalSettings get audioSignalSettings => _audioSignalSettings;

  @override
  Stream<AudioFilterType> get filterChanges => _filterChanges.stream;

  @override
  Stream<AudioSignalSettings> get signalChanges => _signalChanges.stream;

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
    _audioSignalSettings =
        _parseAudioSignalSettings(
          prefs.get(_audioSignalSettingsPrefsKey) ??
              prefs.get(_legacySignalSettingsPrefsKey),
        ) ??
        SettingsService.defaultAudioSignalSettings;
    if (!prefs.containsKey(_audioSignalSettingsPrefsKey) &&
        prefs.containsKey(_legacySignalSettingsPrefsKey)) {
      await prefs.setString(
        _audioSignalSettingsPrefsKey,
        _encodeSignalSettings(_audioSignalSettings),
      );
    }
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
  Future<void> setAudioSignalSettings(AudioSignalSettings settings) async {
    final canonical = _canonicalAudioSignalSettings(settings);
    if (_audioSignalSettings == canonical) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _audioSignalSettingsPrefsKey,
      _encodeSignalSettings(canonical),
    );
    if (!saved) {
      throw StateError('Could not persist audio signal settings');
    }
    _audioSignalSettings = canonical;
    _signalChanges.add(canonical);
  }

  String _encodeSignalSettings(AudioSignalSettings settings) =>
      jsonEncode(<String, Object>{
        'profileId': settings.profile.id,
        'invertPolarity': settings.invertPolarity,
        'sampleRateHz': settings.sampleRate.hz,
      });

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

  AudioSignalSettings? _parseAudioSignalSettings(Object? stored) {
    if (stored is! String) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) return null;
      final profileId = decoded['profileId'];
      final invertPolarity = decoded['invertPolarity'];
      if (profileId is! String || invertPolarity is! bool) return null;
      final storedSampleRate = decoded['sampleRateHz'];
      final sampleRate = storedSampleRate == null
          ? SnapshotTiming.defaultSampleRate
          : SnapshotAudioSampleRate.tryFromHz(storedSampleRate);
      if (sampleRate == null) return null;
      // Preserve the user's last signal choice across the catalog rename.
      final currentProfileId = profileId == '7.5x' ? '7x' : profileId;
      return AudioSignalSettings(
        profile: SnapshotTurboProfiles.resolve(
          id: currentProfileId,
          catalogRevision: SnapshotTurboProfiles.catalogRevision,
        ),
        invertPolarity: invertPolarity,
        sampleRate: sampleRate,
      );
    } catch (_) {
      return null;
    }
  }

  AudioSignalSettings _canonicalAudioSignalSettings(
    AudioSignalSettings settings,
  ) {
    try {
      final profile = SnapshotTurboProfiles.resolve(
        id: settings.profile.id,
        catalogRevision: SnapshotTurboProfiles.catalogRevision,
      );
      if (settings.profile != profile ||
          settings.profile.nominalSpeedMultiplier !=
              profile.nominalSpeedMultiplier) {
        throw const FormatException('Non-catalog timing');
      }
      return AudioSignalSettings(
        profile: profile,
        invertPolarity: settings.invertPolarity,
        sampleRate: settings.sampleRate,
      );
    } catch (_) {
      throw ArgumentError.value(
        settings,
        'settings',
        'Snapshot signal settings must use a current catalog profile',
      );
    }
  }
}
