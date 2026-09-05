import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_error.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';

void main() {
  test('catalog matches the reviewed 48 kHz and receiver table', () {
    SnapshotTurboProfiles.validateProfiles(SnapshotTurboProfiles.values);

    expect(
      SnapshotTurboProfiles.values
          .map(
            (profile) => (
              profile.id,
              profile.nominalSpeedMultiplier,
              profile.zeroTStates,
              profile.oneTStates,
              profile.expectedZeroFrames,
              profile.expectedOneFrames,
              profile.zeroMax,
              profile.bitOneThreshold,
              profile.balancedByteFrames,
            ),
          )
          .toList(),
      [
        ('10x', 10.0, 91, 231, 2, 4, 3, 252, 25),
        ('7x', 7.0, 211, 411, 3, 6, 6, 249, 37),
        ('5x', 5.0, 291, 571, 4, 8, 9, 246, 49),
        ('4x', 4.0, 331, 691, 5, 10, 12, 243, 61),
        ('3x', 3.0, 491, 1011, 7, 14, 18, 237, 85),
        ('2.5x', 2.5, 571, 1211, 8, 17, 21, 234, 101),
        ('2x', 2.0, 691, 1531, 10, 21, 28, 227, 125),
        ('1x', 1.0, 1531, 2971, 21, 41, 59, 196, 249),
      ],
    );
    expect(
      SnapshotTurboProfiles.catalogRevision,
      'snapshot-turbo-speeds-v0',
    );
    expect(SnapshotTiming.turboLeaderPulseCount, 1400);
    expect(SnapshotTiming.receiverLeaderMinimumEdges, 200);
    expect(SnapshotTiming.receiverMiniSyncMax, 0xff);
    expect(
      SnapshotTiming.framesForTStates(
        SnapshotTurboProfiles.speed10x.sync1TStates,
      ),
      4,
    );
    expect(SnapshotTiming.bitLoopMax, 0xff);
    expect(SnapshotTurboProfiles.defaultProfile.id, '5x');
    expect(
      SnapshotTurboProfiles.values.map(
        (profile) => profile.effectiveSpeedMultiplier,
      ),
      [
        closeTo(10, 0.0001),
        closeTo(250 / 37, 0.0001),
        closeTo(250 / 49, 0.0001),
        closeTo(250 / 61, 0.0001),
        closeTo(250 / 85, 0.0001),
        closeTo(250 / 101, 0.0001),
        closeTo(2, 0.0001),
        closeTo(250 / 249, 0.0001),
      ],
    );

    expect(
      SnapshotTurboProfiles.values
          .map(
            (profile) => (
              profile.id,
              profile.leaderTStates,
              profile.sync1TStates,
              profile.sync2TStates,
              profile.payloadMiniSyncTStates,
              profile.expectedLeaderFrames,
              profile.expectedSync1Frames,
              profile.receiverLeaderMax,
              profile.receiverLeaderMin,
              profile.receiverSyncMin,
              profile.receiverLeaderMinCompare,
              profile.receiverSyncMinCompare,
            ),
          )
          .toList(),
      [
        ('10x', 500, 250, 499, 501, 7, 4, 13, 8, 4, 7, 11),
        ('7x', 729, 364, 729, 729, 10, 5, 19, 13, 5, 8, 16),
        ('5x', 1020, 510, 1020, 1020, 14, 7, 26, 18, 8, 10, 20),
        ('4x', 1239, 619, 1239, 1239, 17, 9, 32, 23, 11, 11, 23),
        ('3x', 1677, 838, 1677, 1677, 23, 12, 45, 32, 16, 15, 31),
        ('2.5x', 2041, 1020, 2041, 2041, 28, 14, 55, 39, 19, 18, 38),
        ('2x', 2552, 1276, 2552, 2552, 35, 18, 68, 49, 25, 21, 45),
        ('1x', 5104, 2552, 5104, 5104, 70, 35, 137, 100, 51, 39, 88),
      ],
    );
  });

  test(
    'catalog invariants reject duplicate, reordered, and invalid entries',
    () {
      final duplicate = [...SnapshotTurboProfiles.values];
      duplicate[5] = duplicate[5].copyWith(id: duplicate[4].id);
      expect(
        () => SnapshotTurboProfiles.validateProfiles(duplicate),
        throwsArgumentError,
      );

      final reordered = [...SnapshotTurboProfiles.values];
      final first = reordered.removeAt(0);
      reordered.insert(1, first);
      expect(
        () => SnapshotTurboProfiles.validateProfiles(reordered),
        throwsArgumentError,
      );

      final invalidFrames = [...SnapshotTurboProfiles.values];
      invalidFrames[0] = invalidFrames[0].copyWith(expectedZeroFrames: 3);
      expect(
        () => SnapshotTurboProfiles.validateProfiles(invalidFrames),
        throwsArgumentError,
      );

      final unsafeAcquisition = [...SnapshotTurboProfiles.values];
      unsafeAcquisition[0] = unsafeAcquisition[0].copyWith(
        receiverLeaderMax: 10,
      );
      expect(
        () => SnapshotTurboProfiles.validateProfiles(unsafeAcquisition),
        throwsArgumentError,
      );
    },
  );

  test('stable IDs resolve only inside the matching catalog revision', () {
    for (final profile in SnapshotTurboProfiles.values) {
      expect(
        SnapshotTurboProfiles.resolve(
          id: profile.id,
          catalogRevision: SnapshotTurboProfiles.catalogRevision,
        ),
        profile,
      );
    }
    expect(
      () => SnapshotTurboProfiles.resolve(
        id: '7.5x',
        catalogRevision: SnapshotTurboProfiles.catalogRevision,
      ),
      throwsA(
        isA<SnapshotException>().having(
          (error) => error.code,
          'code',
          SnapshotErrorCode.invalidTurboBlock,
        ),
      ),
    );
    expect(
      () => SnapshotTurboProfiles.resolve(id: '5x', catalogRevision: 'old'),
      throwsA(isA<SnapshotException>()),
    );
  });

  test('every quantized profile is phase-safe in the data polling model', () {
    for (final profile in SnapshotTurboProfiles.values) {
      for (final sampleRate in SnapshotAudioSampleRate.values) {
        expect(
          SnapshotReceiverTimingSimulation.isSafe(
            profile,
            sampleRate: sampleRate,
          ),
          isTrue,
          reason: '${profile.label} at ${sampleRate.label}',
        );
        for (final afterBoundary in [false, true]) {
          final zeroCounts = <int>{};
          final oneCounts = <int>{};
          for (
            var phase = 0;
            phase < SnapshotTiming.receiverDataPollTStates;
            phase++
          ) {
            zeroCounts.add(
              SnapshotReceiverTimingSimulation.pollCount(
                profile,
                one: false,
                phaseTStates: phase,
                afterByteBoundary: afterBoundary,
                sampleRate: sampleRate,
              )!,
            );
            oneCounts.add(
              SnapshotReceiverTimingSimulation.pollCount(
                profile,
                one: true,
                phaseTStates: phase,
                afterByteBoundary: afterBoundary,
                sampleRate: sampleRate,
              )!,
            );
          }
          expect(zeroCounts.every((value) => value <= profile.zeroMax), isTrue);
          expect(oneCounts.every((value) => value > profile.zeroMax), isTrue);
          expect(
            oneCounts.every((value) => value < SnapshotTiming.bitLoopMax),
            isTrue,
          );
        }
      }
    }
  });

  test('every half-sync acquisition profile is phase-safe at 43 T', () {
    for (final profile in SnapshotTurboProfiles.values) {
      for (final sampleRate in SnapshotAudioSampleRate.values) {
        for (final signalRatePermille in [900, 1000, 1100]) {
          expect(
            SnapshotReceiverAcquisitionTimingSimulation.isSafe(
              profile,
              sampleRate: sampleRate,
              signalRatePermille: signalRatePermille,
            ),
            isTrue,
            reason:
                '${profile.label} at ${sampleRate.label}, '
                '$signalRatePermille permille',
          );
        }
        expect(
          profile.expectedSync1FramesAt(sampleRate),
          (profile.expectedLeaderFramesAt(sampleRate) + 1) ~/ 2,
        );
        expect(
          SnapshotTiming.turboLeaderPulseCount *
              profile.expectedLeaderFramesAt(sampleRate),
          greaterThan(0),
        );
      }
    }
  });

  test('44.1 kHz uses its own independently rounded frame catalog', () {
    const rate = SnapshotAudioSampleRate.hz44_1k;
    expect(
      SnapshotTurboProfiles.values
          .map(
            (profile) => (
              profile.expectedLeaderFramesAt(rate),
              profile.expectedSync1FramesAt(rate),
              profile.expectedZeroFramesAt(rate),
              profile.expectedOneFramesAt(rate),
              profile.balancedByteFramesAt(rate),
            ),
          )
          .toList(),
      const [
        (7, 4, 2, 3, 21),
        (10, 5, 3, 6, 37),
        (13, 7, 4, 8, 49),
        (16, 8, 5, 9, 57),
        (22, 11, 7, 13, 81),
        (26, 13, 8, 16, 97),
        (33, 17, 9, 20, 117),
        (65, 33, 20, 38, 233),
      ],
    );
  });

  test('timing fingerprints are unique and output-sensitive', () {
    final fingerprints = SnapshotTurboProfiles.values
        .map((profile) => profile.timingFingerprint)
        .toSet();
    expect(fingerprints, hasLength(SnapshotTurboProfiles.values.length));
    expect(
      SnapshotTurboProfiles.speed10x
          .copyWith(zeroTStates: 92)
          .timingFingerprint,
      isNot(SnapshotTurboProfiles.speed10x.timingFingerprint),
    );
    expect(
      SnapshotTurboProfiles.speed10x
          .copyWith(receiverLeaderMax: 14)
          .timingFingerprint,
      isNot(SnapshotTurboProfiles.speed10x.timingFingerprint),
    );
    expect(
      SnapshotTiming.framesForTStates(SnapshotTiming.turboPreByteDelayTStates),
      SnapshotTiming.preByteDelayFrames,
    );
  });
}
