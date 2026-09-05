enum PcmSampleRate {
  hz48k(48000, '48 kHz'),
  hz44_1k(44100, '44.1 kHz');

  const PcmSampleRate(this.hz, this.label);

  final int hz;
  final String label;

  static PcmSampleRate? tryFromHz(Object? value) {
    for (final sampleRate in values) {
      if (sampleRate.hz == value) return sampleRate;
    }
    return null;
  }
}
