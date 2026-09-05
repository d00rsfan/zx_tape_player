import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class SnapshotSignalSettings {
  const SnapshotSignalSettings({
    required this.profile,
    required this.invertPolarity,
    this.sampleRate = SnapshotTiming.defaultSampleRate,
  });

  final SnapshotTurboProfile profile;
  final bool invertPolarity;
  final SnapshotAudioSampleRate sampleRate;

  @override
  bool operator ==(Object other) =>
      other is SnapshotSignalSettings &&
      other.profile == profile &&
      other.invertPolarity == invertPolarity &&
      other.sampleRate == sampleRate;

  @override
  int get hashCode => Object.hash(profile, invertPolarity, sampleRate);
}

abstract class SettingsService {
  static const AudioFilterType defaultAudioFilter = AudioFilterType.bassBoost;
  static const ZxModel defaultZxModel = ZxModel.zxSpectrum;
  static const SnapshotSignalSettings defaultSnapshotSignalSettings =
      SnapshotSignalSettings(
        profile: SnapshotTurboProfiles.defaultProfile,
        invertPolarity: false,
        sampleRate: SnapshotTiming.defaultSampleRate,
      );

  AudioFilterType get audioFilter;
  ZxModel get zxModel;
  SnapshotSignalSettings get snapshotSignalSettings;

  Future<void> load();

  Future<void> setAudioFilter(AudioFilterType filter);
  Future<void> setZxModel(ZxModel model);
  Future<void> setSnapshotSignalSettings(SnapshotSignalSettings settings);

  Future<void> resetAudioFilterToDefault();
  Future<void> resetZxModelToDefault();

  Stream<AudioFilterType> get filterChanges;
}
