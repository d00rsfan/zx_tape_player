import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

abstract class SettingsService {
  static const AudioFilterType defaultAudioFilter = AudioFilterType.bassBoost;
  static const ZxModel defaultZxModel = ZxModel.zxSpectrum;

  AudioFilterType get audioFilter;
  ZxModel get zxModel;

  Future<void> load();

  Future<void> setAudioFilter(AudioFilterType filter);
  Future<void> setZxModel(ZxModel model);

  Future<void> resetAudioFilterToDefault();
  Future<void> resetZxModelToDefault();

  Stream<AudioFilterType> get filterChanges;
}
