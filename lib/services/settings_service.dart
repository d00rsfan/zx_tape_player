import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

abstract class SettingsService {
  static const AudioFilterType defaultAudioFilter = AudioFilterType.bassBoost;

  AudioFilterType get audioFilter;

  Future<void> load();

  Future<void> setAudioFilter(AudioFilterType filter);

  Future<void> resetAudioFilterToDefault();

  Stream<AudioFilterType> get filterChanges;
}
