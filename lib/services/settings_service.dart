import 'package:zx_tape_player/models/pcm_sample_rate.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class AudioSignalSettings {
  const AudioSignalSettings({
    this.profile = SnapshotTurboProfiles.defaultProfile,
    this.invertPolarity = false,
    this.sampleRate = PcmSampleRate.hz48k,
  });

  /// Turbo timing applies only to snapshot restoration.
  final SnapshotTurboProfile profile;

  /// Global preference, currently implemented only by the snapshot renderer.
  final bool invertPolarity;

  /// Shared by every tape and snapshot conversion.
  final PcmSampleRate sampleRate;

  AudioSignalSettings copyWith({
    SnapshotTurboProfile? profile,
    bool? invertPolarity,
    PcmSampleRate? sampleRate,
  }) => AudioSignalSettings(
    profile: profile ?? this.profile,
    invertPolarity: invertPolarity ?? this.invertPolarity,
    sampleRate: sampleRate ?? this.sampleRate,
  );

  @override
  bool operator ==(Object other) =>
      other is AudioSignalSettings &&
      other.profile == profile &&
      other.invertPolarity == invertPolarity &&
      other.sampleRate == sampleRate;

  @override
  int get hashCode => Object.hash(profile, invertPolarity, sampleRate);
}

abstract class SettingsService {
  static const AudioFilterType defaultAudioFilter = AudioFilterType.bassBoost;
  static const ZxModel defaultZxModel = ZxModel.zxSpectrum;
  static const AudioSignalSettings defaultAudioSignalSettings =
      AudioSignalSettings();

  AudioFilterType get audioFilter;
  ZxModel get zxModel;
  AudioSignalSettings get audioSignalSettings;

  Future<void> load();

  Future<void> setAudioFilter(AudioFilterType filter);
  Future<void> setZxModel(ZxModel model);
  Future<void> setAudioSignalSettings(AudioSignalSettings settings);

  Future<void> resetAudioFilterToDefault();
  Future<void> resetZxModelToDefault();

  Stream<AudioFilterType> get filterChanges;
  Stream<AudioSignalSettings> get signalChanges;
}
