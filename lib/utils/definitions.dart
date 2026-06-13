class Definitions {
  Definitions._();

  static const appTitle = 'ZX Tape Player';
  static const letterType = 'LETTER';
  static const publisherType = 'PUBLISHER';
  // A query starting with a space searches by publisher instead of title.
  static const publisherQueryPrefix = ' ';
  static const pageSize = 30;
  static const supportedTapeExtensions = <String>['tap', 'tzx'];
  static const tapeDir = '%s/tapes';
  static const wafFilePath = '%s/%s.wav';
  static const wavFrequency = 44100;
  static const wavCacheLimitMb = 100;
}
