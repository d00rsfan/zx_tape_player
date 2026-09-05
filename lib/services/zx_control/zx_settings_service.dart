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
  static const _snapshotSignalSettingsPrefsKey = 'snapshotSignalSettings';

  AudioFilterType _audioFilter = SettingsService.defaultAudioFilter;
  ZxModel _zxModel = SettingsService.defaultZxModel;
  SnapshotSignalSettings _snapshotSignalSettings =
      SettingsService.defaultSnapshotSignalSettings;
  bool _loaded = false;
  final _filterChanges = StreamController<AudioFilterType>.broadcast();

  @override
  AudioFilterType get audioFilter => _audioFilter;

  @override
  ZxModel get zxModel => _zxModel;

  @override
  SnapshotSignalSettings get snapshotSignalSettings => _snapshotSignalSettings;

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
    _snapshotSignalSettings =
        _parseSnapshotSignalSettings(
          prefs.get(_snapshotSignalSettingsPrefsKey),
        ) ??
        SettingsService.defaultSnapshotSignalSettings;
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
  Future<void> setSnapshotSignalSettings(
    SnapshotSignalSettings settings,
  ) async {
    final canonical = _canonicalSnapshotSignalSettings(settings);
    if (_snapshotSignalSettings == canonical) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _snapshotSignalSettingsPrefsKey,
      jsonEncode(<String, Object>{
        'profileId': canonical.profile.id,
        'invertPolarity': canonical.invertPolarity,
        'sampleRateHz': canonical.sampleRate.hz,
      }),
    );
    if (!saved) {
      throw StateError('Could not persist snapshot signal settings');
    }
    _snapshotSignalSettings = canonical;
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

  SnapshotSignalSettings? _parseSnapshotSignalSettings(Object? stored) {
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
      return SnapshotSignalSettings(
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

  SnapshotSignalSettings _canonicalSnapshotSignalSettings(
    SnapshotSignalSettings settings,
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
      return SnapshotSignalSettings(
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
