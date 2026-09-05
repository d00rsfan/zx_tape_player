import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_converter.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_renderer.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/snapshots/snapshot_turbo_codec.dart';

import 'snapshot_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const renderer = SnapshotWavRenderer();
  const timelineBuilder = SnapshotTimelineBuilder();
  late SnapshotAssetBundle assets;

  setUpAll(() async {
    assets = SnapshotAssetBundle(
      receiver48Tap: await _asset(
        SnapshotReceiverManifest.receiver48.assetPath,
      ),
      receiver128Tap: await _asset(
        SnapshotReceiverManifest.receiver128.assetPath,
      ),
      registerBlob: await _asset(SnapshotReceiverManifest.registerAssetPath),
    );
  });

  group('edge timeline and WAV', () {
    test('uses independent legacy ceil quantization', () {
      expect(SnapshotWavRenderer.framesForTStates(0), 0);
      expect(SnapshotWavRenderer.framesForTStates(64), 1);
      expect(SnapshotWavRenderer.framesForTStates(91), 2);
      expect(SnapshotWavRenderer.framesForTStates(231), 4);
      expect(SnapshotWavRenderer.framesForTStates(700), 10);
      expect(SnapshotWavRenderer.framesForTStates(2168), 30);
      expect(
        SnapshotWavRenderer.framesForTStates(91) * 2,
        4,
        reason: 'fractional frame remainder must not carry between edges',
      );
    });

    test('quantizes and labels 44.1 kHz output independently', () {
      const rate = SnapshotAudioSampleRate.hz44_1k;
      expect(SnapshotWavRenderer.framesForTStates(91, sampleRate: rate), 2);
      expect(SnapshotWavRenderer.framesForTStates(231, sampleRate: rate), 3);
      final result = renderer.renderTimeline(
        SnapshotEdgeTimeline([
          SnapshotTimelineBlock(
            name: '44.1 kHz tone',
            parts: [
              SnapshotTonePart(const [91, 231], 1),
            ],
          ),
        ]),
        sampleRate: rate,
      );
      final fields = ByteData.sublistView(result.wavBytes);

      expect(result.sampleRate, rate);
      expect(result.totalFrames, 7);
      expect(fields.getUint32(24, Endian.little), 44100);
      expect(fields.getUint32(28, Endian.little), 44100);
      expect(result.blocks.single.sampleRate, rate);
      expect(result.blocks.single.duration, const Duration(microseconds: 158));
      expect(SnapshotWavRenderer.profileIdFor(rate), contains('44100hz'));
    });

    test(
      'uses standard initial polarity and preserves phase across blocks',
      () {
        final timeline = SnapshotEdgeTimeline([
          SnapshotTimelineBlock(
            name: 'edge',
            parts: [
              SnapshotTonePart(const [91], 1),
            ],
          ),
          SnapshotTimelineBlock(
            name: 'pause',
            parts: const [SnapshotPausePart(91)],
          ),
          SnapshotTimelineBlock(
            name: 'next edge',
            parts: [
              SnapshotTonePart(const [91], 1),
            ],
          ),
        ]);

        final result = renderer.renderTimeline(timeline);
        expect(result.wavBytes.sublist(44), [0, 0, 255, 255, 255, 255, 0, 128]);
        expect(result.blocks.map((block) => block.startFrame), [0, 2, 4]);
        expect(result.blocks.map((block) => block.frameLength), [2, 2, 4]);
        expect(result.blocks.last.endFrame, result.totalFrames);
      },
    );

    test('inverted polarity complements PCM without moving any edge', () {
      final timeline = SnapshotEdgeTimeline([
        SnapshotTimelineBlock(
          name: 'tone and pause',
          parts: [
            SnapshotTonePart(const [91, 231], 2),
            const SnapshotPausePart(700),
          ],
        ),
      ]);

      final standard = renderer.renderTimeline(timeline);
      final inverted = renderer.renderTimeline(timeline, invertPolarity: true);

      expect(
        inverted.wavBytes.sublist(0, 44),
        standard.wavBytes.sublist(0, 44),
      );
      expect(inverted.totalFrames, standard.totalFrames);
      expect(
        inverted.blocks.single.startFrame,
        standard.blocks.single.startFrame,
      );
      expect(
        inverted.blocks.single.frameLength,
        standard.blocks.single.frameLength,
      );
      for (var index = 44; index < 44 + standard.totalFrames; index++) {
        expect(inverted.wavBytes[index], 255 - standard.wavBytes[index]);
      }
      expect(
        _transitionIndices(inverted.wavBytes, limit: 20),
        _transitionIndices(standard.wavBytes, limit: 20),
      );
    });

    test('writes deterministic unsigned 8-bit mono RIFF fields', () {
      final timeline = SnapshotEdgeTimeline([
        SnapshotTimelineBlock(
          name: 'tone',
          parts: [
            SnapshotTonePart(const [91, 231], 2),
          ],
        ),
      ]);
      final first = renderer.renderTimeline(timeline);
      final second = renderer.renderTimeline(timeline);
      final bytes = first.wavBytes;
      final fields = ByteData.sublistView(bytes);

      expect(first.wavBytes, second.wavBytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(fields.getUint16(20, Endian.little), 1);
      expect(fields.getUint16(22, Endian.little), 1);
      expect(fields.getUint32(24, Endian.little), 48000);
      expect(fields.getUint16(34, Endian.little), 8);
      expect(fields.getUint32(40, Endian.little), first.totalFrames);
      expect(fields.getUint32(4, Endian.little), bytes.length - 8);
      expect(bytes.sublist(44).toSet(), {0, 128, 255});
    });

    test('writes a terminal edge, neutral tail, and RIFF padding', () {
      final result = renderer.renderTimeline(
        SnapshotEdgeTimeline([
          SnapshotTimelineBlock(
            name: 'one-frame edge',
            parts: [
              SnapshotTonePart(const [64], 1),
            ],
          ),
        ]),
      );
      final fields = ByteData.sublistView(result.wavBytes);

      expect(result.totalFrames, 3);
      expect(result.blocks.single.frameLength, 3);
      expect(result.wavBytes.sublist(44, 47), [0, 255, 128]);
      expect(result.wavBytes.last, 0, reason: 'RIFF pad byte is not PCM');
      expect(result.wavBytes, hasLength(48));
      expect(fields.getUint32(40, Endian.little), 3);
      expect(fields.getUint32(4, Endian.little), 40);
    });
  });

  group('receiver bootstrap', () {
    test('matches ROM pilots, sync, two-edge bits, and first-block golden', () {
      final timeline = timelineBuilder.build(
        assets.receiver48Tap,
        const [],
        turboProfile: SnapshotTurboProfiles.speed10x,
      );
      final firstEvents = timeline.blocks.first.events.toList();

      expect(firstEvents.length, 2824 + 2 + 19 * 8 * 2);
      expect(
        firstEvents.take(2824).every((event) => event.tStates == 2168),
        isTrue,
      );
      expect(firstEvents[2824].tStates, 667);
      expect(firstEvents[2825].tStates, 735);
      expect(
        firstEvents.skip(2826).take(16).map((event) => event.tStates).toSet(),
        {700},
        reason: 'The first TAP flag byte is zero and uses two pulses per bit',
      );

      final result = renderer.render(
        assets.receiver48Tap,
        const [],
        turboProfile: SnapshotTurboProfiles.speed10x,
        invertPolarity: false,
      );
      expect(result.blocks, hasLength(2));
      expect(result.blocks.first.startFrame, 0);
      expect(
        result.blocks.first.frameLength,
        snapshotGoldenBootstrapFirstBlockFrames,
      );
      expect(
        result.blocks[1].startFrame,
        snapshotGoldenBootstrapFirstBlockFrames,
      );
      expect(_transitionIndices(result.wavBytes, limit: 4), [30, 60, 90, 120]);
    });
  });

  group('turbo signal', () {
    test('keeps continuous phase across first and second turbo syncs', () {
      final blocks = [
        _turboBlock(Uint8List.fromList([0x00])),
        _turboBlock(Uint8List.fromList([0x00])),
      ];
      final result = renderer.render(
        assets.receiver48Tap,
        blocks,
        turboProfile: SnapshotTurboProfiles.speed10x,
        invertPolarity: false,
      );
      final pauseFrames = SnapshotWavRenderer.framesForTStates(
        blocks.first.pauseBeforeMilliseconds *
            SnapshotTiming.tStatesPerMillisecond,
      );
      final profile = SnapshotTurboProfiles.speed10x;
      final leaderEdges = SnapshotTiming.turboLeaderPulseCount;
      final leaderFrames =
          leaderEdges *
          SnapshotWavRenderer.framesForTStates(profile.leaderTStates);
      final syncFrames = SnapshotWavRenderer.framesForTStates(
        profile.sync1TStates,
      );

      int syncOffset(int blockIndex) =>
          44 +
          result.blocks[blockIndex + 2].startFrame +
          pauseFrames +
          leaderFrames;

      final firstSync = syncOffset(0);
      final secondSync = syncOffset(1);
      expect(
        result.wavBytes.sublist(firstSync, firstSync + syncFrames),
        everyElement(SnapshotWavRenderer.lowLevel),
      );
      expect(
        result.wavBytes.sublist(secondSync, secondSync + syncFrames),
        everyElement(SnapshotWavRenderer.highLevel),
      );
      expect(syncFrames, 4);
    });

    test('uses one edge per bit and combines the 64T pre-byte delay', () {
      final block = _turboBlock(
        Uint8List.fromList([0x80]),
      ).copyWith(pauseBeforeMilliseconds: 0);
      final timeline = timelineBuilder.build(assets.receiver48Tap, [
        block,
      ], turboProfile: SnapshotTurboProfiles.speed10x);
      final turbo = timeline.blocks[2];
      final parts = turbo.parts;

      final profile = SnapshotTurboProfiles.speed10x;
      expect(
        (parts[0] as SnapshotTonePart).events.length,
        SnapshotTiming.turboLeaderPulseCount,
      );
      expect(
        (parts[0] as SnapshotTonePart).events.every(
          (event) => event.tStates == profile.leaderTStates,
        ),
        isTrue,
      );
      expect(
        (parts[1] as SnapshotTonePart).events.map((event) => event.tStates),
        [profile.sync1TStates, profile.sync2TStates],
      );
      final headerEvents = (parts[2] as SnapshotDataPart).events.toList();
      expect(headerEvents, hasLength(SnapshotTurboHeader.byteLength * 8));
      expect(headerEvents.first.tStates, 91);
      expect(headerEvents[8].tStates, 91 + 64);
      expect(parts[3], isA<SnapshotTonePart>());
      expect(
        (parts[3] as SnapshotTonePart).events.single.tStates,
        profile.payloadMiniSyncTStates,
      );
      final payloadEvents = (parts[4] as SnapshotDataPart).events.toList();
      expect(payloadEvents.map((event) => event.tStates), [
        231,
        91,
        91,
        91,
        91,
        91,
        91,
        91,
      ]);
    });

    test('omits payload mini-sync and edges for an empty payload', () {
      final timeline = timelineBuilder.build(assets.receiver48Tap, [
        _turboBlock(Uint8List(0)),
      ], turboProfile: SnapshotTurboProfiles.speed10x);
      expect(timeline.blocks[2].parts, hasLength(4));
    });

    test('renders exact header and payload vectors for every profile', () {
      final block = _turboBlock(Uint8List.fromList([0x0f, 0xf0]));
      List<SnapshotEdgeEvent>? referenceBootstrap;
      for (final profile in SnapshotTurboProfiles.values) {
        final timeline = timelineBuilder.build(assets.receiver48Tap, [
          block,
        ], turboProfile: profile);
        final bootstrap = timeline.blocks
            .take(2)
            .expand((part) => part.events)
            .toList();
        referenceBootstrap ??= bootstrap;
        expect(
          bootstrap.map((event) => (event.tStates, event.toggleAfter)),
          referenceBootstrap.map((event) => (event.tStates, event.toggleAfter)),
          reason: profile.label,
        );

        final turbo = timeline.blocks[2];
        final leader = turbo.parts[1] as SnapshotTonePart;
        final sync = turbo.parts[2] as SnapshotTonePart;
        final header = turbo.parts[3] as SnapshotDataPart;
        final payloadMiniSync = turbo.parts[4] as SnapshotTonePart;
        final payload = turbo.parts[5] as SnapshotDataPart;
        expect(leader.events, hasLength(SnapshotTiming.turboLeaderPulseCount));
        expect(
          leader.events.every(
            (event) => event.tStates == profile.leaderTStates,
          ),
          isTrue,
        );
        expect(sync.events.map((event) => event.tStates), [
          profile.sync1TStates,
          profile.sync2TStates,
        ]);
        expect(
          payloadMiniSync.events.single.tStates,
          profile.payloadMiniSyncTStates,
        );
        expect(header.zeroPattern, [profile.zeroTStates]);
        expect(header.onePattern, [profile.oneTStates]);
        expect(payload.zeroPattern, [profile.zeroTStates]);
        expect(payload.onePattern, [profile.oneTStates]);
        expect(header.preByteDelayTStates, 64);
        expect(payload.preByteDelayTStates, 64);

        final payloadEvents = payload.events.toList();
        expect(payloadEvents, hasLength(16));
        expect(payloadEvents[8].tStates, profile.oneTStates + 64);
        final payloadFrames = payloadEvents.fold<int>(
          0,
          (sum, event) =>
              sum + SnapshotWavRenderer.framesForTStates(event.tStates),
        );
        expect(payloadFrames, 2 * profile.balancedByteFrames - 1);

        final rendered = renderer.render(
          assets.receiver48Tap,
          [block],
          turboProfile: profile,
          invertPolarity: false,
        );
        expect(rendered.blocks[2].startFrame, rendered.blocks[1].endFrame);
        expect(rendered.blocks[2].endFrame, rendered.totalFrames);
      }
    });
  });

  group('complete conversion', () {
    test('5x and 10x preserve logical bytes and restore ordering', () {
      final fixture = makeSna128(currentBank: 3);
      final fast = const SnapshotConverter().convert(
        snapshotBytes: fixture,
        fileName: 'state.sna',
        assets: assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
        invertPolarity: false,
      );
      final slow = const SnapshotConverter().convert(
        snapshotBytes: fixture,
        fileName: 'state.sna',
        assets: assets,
        turboProfile: SnapshotTurboProfiles.speed5x,
        invertPolarity: false,
      );

      expect(
        slow.turboBlocks.map((block) => block.headerBytes),
        fast.turboBlocks.map((block) => block.headerBytes),
      );
      expect(
        slow.turboBlocks.map((block) => block.payload),
        fast.turboBlocks.map((block) => block.payload),
      );
      expect(
        slow.restorePlan.blocks.map(
          (block) =>
              (block.name, block.start, block.bank, block.executionAddress),
        ),
        fast.restorePlan.blocks.map(
          (block) =>
              (block.name, block.start, block.bank, block.executionAddress),
        ),
      );
      expect(
        slow.wav.blocks.first.frameLength,
        fast.wav.blocks.first.frameLength,
      );
      expect(slow.wav.wavBytes, isNot(fast.wav.wavBytes));
      expect(slow.wav.totalFrames, greaterThan(fast.wav.totalFrames));
      expect(slow.restorePlan.turboProfile.bitOneThreshold, 246);
      expect(fast.restorePlan.turboProfile.bitOneThreshold, 252);
    });

    test('derives contiguous block frames and monotonic progress', () {
      final ram = make48kRam()..fillRange(0, 48 * 1024, 0x33);
      final progress = <int>[];
      final conversion = const SnapshotConverter().convert(
        snapshotBytes: makeZ80V1(ram: ram),
        fileName: 'state.z80',
        assets: assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
        invertPolarity: false,
        onProgress: progress.add,
      );

      expect(
        conversion.wav.blocks,
        hasLength(2 + conversion.turboBlocks.length),
      );
      expect(conversion.wav.blocks.first.startFrame, 0);
      for (var index = 1; index < conversion.wav.blocks.length; index++) {
        expect(
          conversion.wav.blocks[index].startFrame,
          conversion.wav.blocks[index - 1].endFrame,
        );
      }
      expect(conversion.wav.blocks.last.endFrame, conversion.wav.totalFrames);
      expect(progress.first, 0);
      expect(progress.last, 100);
      expect(progress, orderedEquals([...progress]..sort()));
      expect(conversion.turboBlocks.first.pauseBeforeMilliseconds, 100);
      expect(conversion.turboBlocks[1].pauseBeforeMilliseconds, 153);
    });

    test('is deterministic and has no filter-dependent input', () {
      final fixture = makeSna128(currentBank: 3);
      final first = const SnapshotConverter().convert(
        snapshotBytes: fixture,
        fileName: 'state.sna',
        assets: assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
        invertPolarity: false,
      );
      final second = const SnapshotConverter().convert(
        snapshotBytes: fixture,
        fileName: 'state.sna',
        assets: assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
        invertPolarity: false,
      );

      expect(first.wav.wavBytes, second.wav.wavBytes);
      expect(
        first.wav.blocks.map((block) => block.startFrame),
        second.wav.blocks.map((block) => block.startFrame),
      );
    });
  });
}

SnapshotTurboBlock _turboBlock(Uint8List payload) => SnapshotTurboBlock(
  name: 'Turbo test',
  header: SnapshotTurboHeader(
    length: payload.length,
    loadAddress: payload.isEmpty ? 0 : 0x8000,
    destinationAddress: 0,
    compression: SnapshotCompressionType.none,
    payloadChecksum: snapshotPayloadChecksum(payload),
    action: SnapshotPostCommand.loadNext.wireValue,
    clearOrBank: 0,
    codeForMost: 0,
    decompressionCounter: 0,
    codeForMultiples: 0,
    valueForMost: 0,
  ),
  payload: payload,
  originalLength: payload.length,
  pauseBeforeMilliseconds: 100,
);

List<int> _transitionIndices(Uint8List wav, {required int limit}) {
  final result = <int>[];
  final dataLength = ByteData.sublistView(wav).getUint32(40, Endian.little);
  final pcm = wav.sublist(44, 44 + dataLength);
  for (var index = 1; index < pcm.length && result.length < limit; index++) {
    if (pcm[index] != pcm[index - 1]) result.add(index);
  }
  return result;
}

Future<Uint8List> _asset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
