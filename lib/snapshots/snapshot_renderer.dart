import 'dart:typed_data';

import 'snapshot_error.dart';
import 'snapshot_timing.dart';
import 'snapshot_turbo_codec.dart';

class SnapshotEdgeEvent {
  const SnapshotEdgeEvent(this.tStates, {required this.toggleAfter});

  final int tStates;
  final bool toggleAfter;
}

sealed class SnapshotTimelinePart {
  const SnapshotTimelinePart();

  Iterable<SnapshotEdgeEvent> get events;
}

class SnapshotPausePart extends SnapshotTimelinePart {
  const SnapshotPausePart(this.tStates);

  final int tStates;

  @override
  Iterable<SnapshotEdgeEvent> get events sync* {
    if (tStates > 0) yield SnapshotEdgeEvent(tStates, toggleAfter: false);
  }
}

class SnapshotTonePart extends SnapshotTimelinePart {
  SnapshotTonePart(Iterable<int> pattern, this.repetitions)
    : pattern = List.unmodifiable(pattern) {
    if (this.pattern.isEmpty || this.pattern.any((value) => value <= 0)) {
      throw ArgumentError.value(
        pattern,
        'pattern',
        'Durations must be positive',
      );
    }
    if (repetitions < 0) {
      throw ArgumentError.value(repetitions, 'repetitions');
    }
  }

  final List<int> pattern;
  final int repetitions;

  @override
  Iterable<SnapshotEdgeEvent> get events sync* {
    for (var repetition = 0; repetition < repetitions; repetition++) {
      for (final duration in pattern) {
        yield SnapshotEdgeEvent(duration, toggleAfter: true);
      }
    }
  }
}

class SnapshotDataPart extends SnapshotTimelinePart {
  SnapshotDataPart({
    required Uint8List data,
    required Iterable<int> zeroPattern,
    required Iterable<int> onePattern,
    this.preByteDelayTStates = 0,
  }) : data = Uint8List.fromList(data),
       zeroPattern = List.unmodifiable(zeroPattern),
       onePattern = List.unmodifiable(onePattern) {
    if (this.zeroPattern.isEmpty || this.onePattern.isEmpty) {
      throw ArgumentError('Bit patterns cannot be empty');
    }
    if (this.zeroPattern.any((value) => value <= 0) ||
        this.onePattern.any((value) => value <= 0) ||
        preByteDelayTStates < 0) {
      throw ArgumentError('Signal durations cannot be negative or zero');
    }
  }

  final Uint8List data;
  final List<int> zeroPattern;
  final List<int> onePattern;
  final int preByteDelayTStates;

  @override
  Iterable<SnapshotEdgeEvent> get events sync* {
    for (var byteIndex = 0; byteIndex < data.length; byteIndex++) {
      final byte = data[byteIndex];
      for (var bitIndex = 7; bitIndex >= 0; bitIndex--) {
        final isOne = (byte & (1 << bitIndex)) != 0;
        final pattern = isOne ? onePattern : zeroPattern;
        for (var pulseIndex = 0; pulseIndex < pattern.length; pulseIndex++) {
          var duration = pattern[pulseIndex];
          if (byteIndex > 0 && bitIndex == 7 && pulseIndex == 0) {
            duration += preByteDelayTStates;
          }
          yield SnapshotEdgeEvent(duration, toggleAfter: true);
        }
      }
    }
  }
}

class SnapshotTimelineBlock {
  SnapshotTimelineBlock({
    required this.name,
    required Iterable<SnapshotTimelinePart> parts,
  }) : parts = List.unmodifiable(parts);

  final String name;
  final List<SnapshotTimelinePart> parts;

  Iterable<SnapshotEdgeEvent> get events sync* {
    for (final part in parts) {
      yield* part.events;
    }
  }
}

class SnapshotEdgeTimeline {
  SnapshotEdgeTimeline(Iterable<SnapshotTimelineBlock> blocks)
    : blocks = List.unmodifiable(blocks);

  final List<SnapshotTimelineBlock> blocks;

  Iterable<SnapshotEdgeEvent> get events sync* {
    for (final block in blocks) {
      yield* block.events;
    }
  }
}

class SnapshotRenderedBlock {
  const SnapshotRenderedBlock({
    required this.name,
    required this.startFrame,
    required this.frameLength,
    required this.sampleRate,
  });

  final String name;
  final int startFrame;
  final int frameLength;
  final SnapshotAudioSampleRate sampleRate;

  int get endFrame => startFrame + frameLength;
  Duration get start =>
      SnapshotWavRenderer.framesToDuration(startFrame, sampleRate: sampleRate);
  Duration get duration =>
      SnapshotWavRenderer.framesToDuration(frameLength, sampleRate: sampleRate);
}

class SnapshotWavResult {
  SnapshotWavResult({
    required Uint8List wavBytes,
    required this.totalFrames,
    required List<SnapshotRenderedBlock> blocks,
    required this.sampleRate,
  }) : wavBytes = Uint8List.fromList(wavBytes),
       blocks = List.unmodifiable(blocks);

  final Uint8List wavBytes;
  final int totalFrames;
  final List<SnapshotRenderedBlock> blocks;
  final SnapshotAudioSampleRate sampleRate;
}

class SnapshotTimelineBuilder {
  const SnapshotTimelineBuilder();

  SnapshotEdgeTimeline build(
    Uint8List receiverTap,
    List<SnapshotTurboBlock> turboBlocks, {
    required SnapshotTurboProfile turboProfile,
  }) {
    final tapBlocks = _parseTap(receiverTap);
    if (tapBlocks.length != 2) {
      throw SnapshotException(
        SnapshotErrorCode.invalidAsset,
        'Receiver TAP contains ${tapBlocks.length} blocks; expected 2',
      );
    }
    final blocks = <SnapshotTimelineBlock>[
      _romBlock(
        'Snapshot bootstrap',
        tapBlocks[0],
        SnapshotTiming.bootstrapLeaderMilliseconds,
      ),
      _romBlock(
        'Snapshot receiver',
        tapBlocks[1],
        SnapshotTiming.receiverLeaderMilliseconds,
      ),
    ];
    for (var index = 0; index < turboBlocks.length; index++) {
      final turbo = turboBlocks[index];
      blocks.add(
        SnapshotTimelineBlock(
          name: turbo.name,
          parts: [
            if (turbo.pauseBeforeMilliseconds > 0)
              SnapshotPausePart(
                turbo.pauseBeforeMilliseconds *
                    SnapshotTiming.tStatesPerMillisecond,
              ),
            SnapshotTonePart([
              turboProfile.leaderTStates,
              turboProfile.leaderTStates,
            ], SnapshotTiming.turboLeaderPulseCount ~/ 2),
            SnapshotTonePart([
              turboProfile.sync1TStates,
              turboProfile.sync2TStates,
            ], 1),
            SnapshotDataPart(
              data: turbo.headerBytes,
              zeroPattern: [turboProfile.zeroTStates],
              onePattern: [turboProfile.oneTStates],
              preByteDelayTStates: SnapshotTiming.turboPreByteDelayTStates,
            ),
            if (turbo.payload.isNotEmpty) ...[
              SnapshotTonePart([turboProfile.payloadMiniSyncTStates], 1),
              SnapshotDataPart(
                data: turbo.payload,
                zeroPattern: [turboProfile.zeroTStates],
                onePattern: [turboProfile.oneTStates],
                preByteDelayTStates: SnapshotTiming.turboPreByteDelayTStates,
              ),
            ],
          ],
        ),
      );
    }
    return SnapshotEdgeTimeline(blocks);
  }

  SnapshotTimelineBlock _romBlock(
    String name,
    Uint8List data,
    int leaderMilliseconds,
  ) => SnapshotTimelineBlock(
    name: name,
    parts: [
      SnapshotTonePart(
        const [
          SnapshotTiming.romLeaderTStates,
          SnapshotTiming.romLeaderTStates,
        ],
        _toneRepetitions(
          leaderMilliseconds,
          2 * SnapshotTiming.romLeaderTStates,
        ),
      ),
      SnapshotTonePart(const [
        SnapshotTiming.romSync1TStates,
        SnapshotTiming.romSync2TStates,
      ], 1),
      SnapshotDataPart(
        data: data,
        zeroPattern: const [
          SnapshotTiming.romQuickZeroTStates,
          SnapshotTiming.romQuickZeroTStates,
        ],
        onePattern: const [
          2 * SnapshotTiming.romQuickZeroTStates,
          2 * SnapshotTiming.romQuickZeroTStates,
        ],
      ),
    ],
  );

  int _toneRepetitions(int milliseconds, int patternTStates) =>
      (milliseconds * SnapshotTiming.tStatesPerMillisecond) ~/ patternTStates;

  List<Uint8List> _parseTap(Uint8List tap) {
    final blocks = <Uint8List>[];
    var offset = 0;
    while (offset < tap.length) {
      if (offset + 2 > tap.length) {
        throw SnapshotException(
          SnapshotErrorCode.invalidAsset,
          'Truncated receiver TAP length at byte $offset',
          offset: offset,
        );
      }
      final length = tap[offset] | (tap[offset + 1] << 8);
      final start = offset + 2;
      final end = start + length;
      if (length < 2 || end > tap.length) {
        throw SnapshotException(
          SnapshotErrorCode.invalidAsset,
          'Invalid receiver TAP block length $length',
          offset: offset,
        );
      }
      blocks.add(Uint8List.fromList(tap.sublist(start, end)));
      offset = end;
    }
    return blocks;
  }
}

class SnapshotWavRenderer {
  const SnapshotWavRenderer({
    this.timelineBuilder = const SnapshotTimelineBuilder(),
  });

  static const int sampleRate = SnapshotTiming.sampleRate;
  static const int bitsPerSample = 8;
  static const int channels = 1;
  static const String profileId =
      '${sampleRate}hz-${bitsPerSample}bit-${channels}ch-'
      'legacy-ceil-terminal-edge-riff-pad-v2';
  static String profileIdFor(SnapshotAudioSampleRate sampleRate) =>
      '${sampleRate.hz}hz-${bitsPerSample}bit-${channels}ch-'
      'legacy-ceil-terminal-edge-riff-pad-v2';
  static const int lowLevel = 0;
  static const int highLevel = 255;
  static const int silenceLevel = 128;
  static const int terminalTailFrames = 2;

  final SnapshotTimelineBuilder timelineBuilder;

  SnapshotWavResult render(
    Uint8List receiverTap,
    List<SnapshotTurboBlock> turboBlocks, {
    required SnapshotTurboProfile turboProfile,
    required bool invertPolarity,
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
    void Function(int progress)? onProgress,
  }) => renderTimeline(
    timelineBuilder.build(receiverTap, turboBlocks, turboProfile: turboProfile),
    invertPolarity: invertPolarity,
    sampleRate: sampleRate,
    onProgress: onProgress,
  );

  SnapshotWavResult renderTimeline(
    SnapshotEdgeTimeline timeline, {
    bool invertPolarity = false,
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
    void Function(int progress)? onProgress,
  }) {
    final metadata = <SnapshotRenderedBlock>[];
    var totalFrames = 0;
    var hasEvents = false;
    for (final block in timeline.blocks) {
      final start = totalFrames;
      for (final event in block.events) {
        hasEvents = true;
        totalFrames += framesForTStates(event.tStates, sampleRate: sampleRate);
      }
      metadata.add(
        SnapshotRenderedBlock(
          name: block.name,
          startFrame: start,
          frameLength: totalFrames - start,
          sampleRate: sampleRate,
        ),
      );
    }
    if (hasEvents) {
      totalFrames += terminalTailFrames;
      final last = metadata.removeLast();
      metadata.add(
        SnapshotRenderedBlock(
          name: last.name,
          startFrame: last.startFrame,
          frameLength: last.frameLength + terminalTailFrames,
          sampleRate: sampleRate,
        ),
      );
    }

    final paddingLength = totalFrames.isOdd ? 1 : 0;
    final wav = Uint8List(44 + totalFrames + paddingLength);
    _writeWavHeader(wav, totalFrames, sampleRate);
    var writeOffset = 44;
    var level = invertPolarity ? highLevel : lowLevel;
    var lastProgress = -1;
    void report(int value) {
      final clamped = value.clamp(0, 100);
      if (clamped > lastProgress) {
        lastProgress = clamped;
        onProgress?.call(clamped);
      }
    }

    report(0);
    for (
      var blockIndex = 0;
      blockIndex < timeline.blocks.length;
      blockIndex++
    ) {
      for (final event in timeline.blocks[blockIndex].events) {
        final frames = framesForTStates(event.tStates, sampleRate: sampleRate);
        wav.fillRange(writeOffset, writeOffset + frames, level);
        writeOffset += frames;
        if (event.toggleAfter) level = level == lowLevel ? highLevel : lowLevel;
      }
      report(((blockIndex + 1) * 100) ~/ timeline.blocks.length);
    }
    if (hasEvents) {
      // The last edge otherwise exists only as renderer state, not in PCM.
      // Emit one frame at that post-edge level, followed by unsigned 8-bit
      // silence. This mirrors the reference generator's terminal sample/tail.
      wav[writeOffset++] = level;
      wav[writeOffset++] = invertPolarity
          ? highLevel - silenceLevel
          : silenceLevel;
    }
    report(100);
    if (writeOffset != 44 + totalFrames) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidTurboBlock,
        'Rendered PCM length differs from planned edge timeline',
      );
    }
    return SnapshotWavResult(
      wavBytes: wav,
      totalFrames: totalFrames,
      blocks: metadata,
      sampleRate: sampleRate,
    );
  }

  static int framesForTStates(
    int tStates, {
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
  }) => SnapshotTiming.framesForTStates(tStates, sampleRate: sampleRate.hz);

  static Duration framesToDuration(
    int frames, {
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
  }) => Duration(
    microseconds: (frames * Duration.microsecondsPerSecond) ~/ sampleRate.hz,
  );

  void _writeWavHeader(
    Uint8List bytes,
    int dataLength,
    SnapshotAudioSampleRate sampleRate,
  ) {
    final data = ByteData.sublistView(bytes);
    void ascii(int offset, String text) {
      for (var index = 0; index < text.length; index++) {
        bytes[offset + index] = text.codeUnitAt(index);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, bytes.length - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate.hz, Endian.little);
    data.setUint32(28, sampleRate.hz * channels, Endian.little);
    data.setUint16(32, channels, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);
  }
}
