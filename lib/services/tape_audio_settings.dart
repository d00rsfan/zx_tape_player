import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:zx_tape_player/models/pcm_sample_rate.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

/// Captured together for conversion, cache lookup and binding to the player.
class TapeAudioSettings {
  const TapeAudioSettings({required this.filter, required this.sampleRate});

  final AudioFilterType filter;
  final PcmSampleRate sampleRate;

  String cacheKey(String sourcePath) {
    final hash = sha1.convert(utf8.encode(sourcePath));
    // Invalidate recordings generated before the TZX waveform fixes.
    return '${hash}_wavx1.4.0_${filter.name}_${sampleRate.hz}';
  }

  @override
  bool operator ==(Object other) =>
      other is TapeAudioSettings &&
      other.filter == filter &&
      other.sampleRate == sampleRate;

  @override
  int get hashCode => Object.hash(filter, sampleRate);
}
