import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/models/pcm_sample_rate.dart';
import 'package:zx_tape_player/services/tape_audio_settings.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

void main() {
  test(
    'WAV caches separate source, sample rate, filter and converter revision',
    () {
      final keys = <String>{};
      for (final source in ['/one/game.tap', '/two/game.tap']) {
        for (final rate in PcmSampleRate.values) {
          for (final filter in [
            AudioFilterType.none,
            AudioFilterType.bassBoost,
          ]) {
            final settings = TapeAudioSettings(
              filter: filter,
              sampleRate: rate,
            );
            expect(keys.add(settings.cacheKey(source)), isTrue);
            expect(settings.cacheKey(source), contains('wavx1.4.0'));
          }
        }
      }
    },
  );
}
