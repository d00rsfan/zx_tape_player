class Definitions {
  Definitions._();

  static const appTitle = 'ZX Tape Player';
  static const letterType = 'LETTER';
  static const publisherType = 'PUBLISHER';
  // A query starting with a space searches by publisher instead of title.
  static const publisherQueryPrefix = ' ';
  static const pageSize = 30;
  // Formats the app can play: TZX recordings for every supported model,
  // ZX Spectrum TAP, ZX81 P/81/P81, and ZX80 O/80. The extensions requested
  // from ZXInfo are model-specific; see ZxModel.remoteTapeExtensions.
  static const supportedTapeExtensions = <String>[
    'tap',
    'tzx',
    'p',
    '81',
    'p81',
    'o',
    '80',
  ];
  static const tapeDir = '%s/tapes';
  static const wafFilePath = '%s/%s.wav';
  static const wavFrequency = 44100;
  static const wavCacheLimitMb = 100;
}
