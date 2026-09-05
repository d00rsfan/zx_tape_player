import 'snapshot_error.dart';

enum SnapshotAudioSampleRate {
  hz48k(48000, '48 kHz'),
  hz44_1k(44100, '44.1 kHz');

  const SnapshotAudioSampleRate(this.hz, this.label);

  final int hz;
  final String label;

  static SnapshotAudioSampleRate? tryFromHz(Object? value) {
    for (final sampleRate in values) {
      if (sampleRate.hz == value) return sampleRate;
    }
    return null;
  }
}

/// Immutable, jointly receiver/WAV-compatible timing for snapshot turbo data.
class SnapshotTurboProfile {
  const SnapshotTurboProfile({
    required this.id,
    required this.nominalSpeedMultiplier,
    required this.leaderTStates,
    required this.sync1TStates,
    required this.sync2TStates,
    required this.payloadMiniSyncTStates,
    required this.zeroTStates,
    required this.oneTStates,
    required this.expectedLeaderFrames,
    required this.expectedSync1Frames,
    required this.expectedSync2Frames,
    required this.expectedPayloadMiniSyncFrames,
    required this.expectedZeroFrames,
    required this.expectedOneFrames,
    required this.receiverLeaderMax,
    required this.receiverLeaderMin,
    required this.receiverSyncMin,
    required this.zeroMax,
  });

  final String id;
  final double nominalSpeedMultiplier;
  final int leaderTStates;
  final int sync1TStates;
  final int sync2TStates;
  final int payloadMiniSyncTStates;
  final int zeroTStates;
  final int oneTStates;
  final int expectedLeaderFrames;
  final int expectedSync1Frames;
  final int expectedSync2Frames;
  final int expectedPayloadMiniSyncFrames;
  final int expectedZeroFrames;
  final int expectedOneFrames;
  final int receiverLeaderMax;
  final int receiverLeaderMin;
  final int receiverSyncMin;
  final int zeroMax;

  String get label {
    final wholeSpeed = nominalSpeedMultiplier.truncateToDouble();
    final value = nominalSpeedMultiplier == wholeSpeed
        ? wholeSpeed.toInt().toString()
        : nominalSpeedMultiplier.toStringAsFixed(1);
    return '${value}x';
  }

  int get bitOneThreshold => SnapshotTiming.bitLoopMax - zeroMax;
  int get receiverLeaderMinCompare => receiverLeaderMax + 2 - receiverLeaderMin;
  int get receiverSyncMinCompare => receiverLeaderMax + 2 - receiverSyncMin;
  int get leaderFrames =>
      SnapshotTiming.turboLeaderPulseCount * expectedLeaderFrames;
  int get balancedByteFrames =>
      4 * (expectedZeroFrames + expectedOneFrames) +
      SnapshotTiming.preByteDelayFrames;
  int expectedLeaderFramesAt(SnapshotAudioSampleRate sampleRate) =>
      SnapshotTiming.framesForTStates(leaderTStates, sampleRate: sampleRate.hz);
  int expectedSync1FramesAt(SnapshotAudioSampleRate sampleRate) =>
      SnapshotTiming.framesForTStates(sync1TStates, sampleRate: sampleRate.hz);
  int expectedSync2FramesAt(SnapshotAudioSampleRate sampleRate) =>
      SnapshotTiming.framesForTStates(sync2TStates, sampleRate: sampleRate.hz);
  int expectedPayloadMiniSyncFramesAt(SnapshotAudioSampleRate sampleRate) =>
      SnapshotTiming.framesForTStates(
        payloadMiniSyncTStates,
        sampleRate: sampleRate.hz,
      );
  int expectedZeroFramesAt(SnapshotAudioSampleRate sampleRate) =>
      SnapshotTiming.framesForTStates(zeroTStates, sampleRate: sampleRate.hz);
  int expectedOneFramesAt(SnapshotAudioSampleRate sampleRate) =>
      SnapshotTiming.framesForTStates(oneTStates, sampleRate: sampleRate.hz);
  int balancedByteFramesAt(SnapshotAudioSampleRate sampleRate) =>
      4 * (expectedZeroFramesAt(sampleRate) + expectedOneFramesAt(sampleRate)) +
      SnapshotTiming.framesForTStates(
        SnapshotTiming.turboPreByteDelayTStates,
        sampleRate: sampleRate.hz,
      );
  double get effectiveSpeedMultiplier =>
      10 *
      SnapshotTurboProfiles.speed10x.balancedByteFrames /
      balancedByteFrames;
  double effectiveSpeedMultiplierAt(SnapshotAudioSampleRate sampleRate) =>
      10 *
      SnapshotTurboProfiles.speed10x.balancedByteFramesAt(sampleRate) /
      balancedByteFramesAt(sampleRate);

  /// Stable cache material. A catalog revision still namespaces this value so
  /// correcting a profile later cannot reuse an old waveform accidentally.
  String get timingFingerprint =>
      'l$leaderTStates-s$sync1TStates-$sync2TStates-'
      'm$payloadMiniSyncTStates-'
      'lf$expectedLeaderFrames-sf$expectedSync1Frames-'
      '$expectedSync2Frames-$expectedPayloadMiniSyncFrames-'
      'la$receiverLeaderMax-$receiverLeaderMin-$receiverSyncMin-'
      'z$zeroTStates-o$oneTStates-'
      'f$expectedZeroFrames-$expectedOneFrames-'
      'zm$zeroMax-th$bitOneThreshold';

  SnapshotTurboProfile copyWith({
    String? id,
    double? nominalSpeedMultiplier,
    int? leaderTStates,
    int? sync1TStates,
    int? sync2TStates,
    int? payloadMiniSyncTStates,
    int? zeroTStates,
    int? oneTStates,
    int? expectedLeaderFrames,
    int? expectedSync1Frames,
    int? expectedSync2Frames,
    int? expectedPayloadMiniSyncFrames,
    int? expectedZeroFrames,
    int? expectedOneFrames,
    int? receiverLeaderMax,
    int? receiverLeaderMin,
    int? receiverSyncMin,
    int? zeroMax,
  }) => SnapshotTurboProfile(
    id: id ?? this.id,
    nominalSpeedMultiplier:
        nominalSpeedMultiplier ?? this.nominalSpeedMultiplier,
    leaderTStates: leaderTStates ?? this.leaderTStates,
    sync1TStates: sync1TStates ?? this.sync1TStates,
    sync2TStates: sync2TStates ?? this.sync2TStates,
    payloadMiniSyncTStates:
        payloadMiniSyncTStates ?? this.payloadMiniSyncTStates,
    zeroTStates: zeroTStates ?? this.zeroTStates,
    oneTStates: oneTStates ?? this.oneTStates,
    expectedLeaderFrames: expectedLeaderFrames ?? this.expectedLeaderFrames,
    expectedSync1Frames: expectedSync1Frames ?? this.expectedSync1Frames,
    expectedSync2Frames: expectedSync2Frames ?? this.expectedSync2Frames,
    expectedPayloadMiniSyncFrames:
        expectedPayloadMiniSyncFrames ?? this.expectedPayloadMiniSyncFrames,
    expectedZeroFrames: expectedZeroFrames ?? this.expectedZeroFrames,
    expectedOneFrames: expectedOneFrames ?? this.expectedOneFrames,
    receiverLeaderMax: receiverLeaderMax ?? this.receiverLeaderMax,
    receiverLeaderMin: receiverLeaderMin ?? this.receiverLeaderMin,
    receiverSyncMin: receiverSyncMin ?? this.receiverSyncMin,
    zeroMax: zeroMax ?? this.zeroMax,
  );

  @override
  bool operator ==(Object other) =>
      other is SnapshotTurboProfile &&
      other.id == id &&
      other.timingFingerprint == timingFingerprint;

  @override
  int get hashCode => Object.hash(id, timingFingerprint);
}

/// All profile-independent snapshot protocol timing and receiver patch values.
class SnapshotTiming {
  const SnapshotTiming._();

  static const int spectrumClock = 3500000;
  static const SnapshotAudioSampleRate defaultSampleRate =
      SnapshotAudioSampleRate.hz48k;
  static const int sampleRate = 48000;
  static const int tStatesPerMillisecond = 3500;

  static const int romLeaderTStates = 2168;
  static const int romSync1TStates = 667;
  static const int romSync2TStates = 735;
  static const int romQuickZeroTStates = 700;
  static const int bootstrapLeaderMilliseconds = 1750;
  static const int receiverLeaderMilliseconds = 1500;

  // Upstream's 200 ms / 500-T leader contains 1,400 half-wave pulses. Keep
  // that edge count fixed while profiles change each pulse's duration.
  static const int turboLeaderPulseCount = 1400;
  static const int receiverLeaderMinimumEdges = 200;
  static const int turboPreByteDelayTStates = 64;

  static const int receiverAcquisitionPollTStates = 43;
  static const int receiverAcquisitionMinRatePermille = 900;
  static const int receiverAcquisitionMaxRatePermille = 1100;
  // From one detected EAR sample to the first sample in the next acquisition
  // wait. These include the fixed Z80 work between WAIT_FOR_EDGE calls.
  static const int receiverLeaderLoop1FirstPollTStates = 127;
  static const int receiverLeaderLoop2FirstPollTStates = 130;
  static const int receiverMiniSyncFirstPollTStates = 164;
  static const int receiverMiniSyncMax = 0xff;
  static const int receiverFirstDataPollTStates = 91;
  static const int receiverDataPollTStates = 40;
  static const int bitLoopMax = 255;
  static const int ioInitial = 0x0a;
  static const int ioXor = 0x47;

  static int framesForTStates(
    int tStates, {
    int sampleRate = SnapshotTiming.sampleRate,
  }) {
    if (tStates < 0) throw ArgumentError.value(tStates, 'tStates');
    if (SnapshotAudioSampleRate.tryFromHz(sampleRate) == null) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
    if (tStates == 0) return 0;
    return (tStates * sampleRate + spectrumClock - 1) ~/ spectrumClock;
  }

  static const int preByteDelayFrames = 1;
}

class SnapshotTurboProfiles {
  const SnapshotTurboProfiles._();

  static const String catalogRevision = 'snapshot-turbo-speeds-v0';

  static const SnapshotTurboProfile speed10x = SnapshotTurboProfile(
    id: '10x',
    nominalSpeedMultiplier: 10,
    leaderTStates: 500,
    sync1TStates: 250,
    sync2TStates: 499,
    payloadMiniSyncTStates: 501,
    zeroTStates: 91,
    oneTStates: 231,
    expectedLeaderFrames: 7,
    expectedSync1Frames: 4,
    expectedSync2Frames: 7,
    expectedPayloadMiniSyncFrames: 7,
    expectedZeroFrames: 2,
    expectedOneFrames: 4,
    receiverLeaderMax: 13,
    receiverLeaderMin: 8,
    receiverSyncMin: 4,
    zeroMax: 3,
  );
  static const SnapshotTurboProfile speed7x = SnapshotTurboProfile(
    id: '7x',
    nominalSpeedMultiplier: 7,
    leaderTStates: 729,
    sync1TStates: 364,
    sync2TStates: 729,
    payloadMiniSyncTStates: 729,
    zeroTStates: 211,
    oneTStates: 411,
    expectedLeaderFrames: 10,
    expectedSync1Frames: 5,
    expectedSync2Frames: 10,
    expectedPayloadMiniSyncFrames: 10,
    expectedZeroFrames: 3,
    expectedOneFrames: 6,
    receiverLeaderMax: 19,
    receiverLeaderMin: 13,
    receiverSyncMin: 5,
    zeroMax: 6,
  );
  static const SnapshotTurboProfile speed5x = SnapshotTurboProfile(
    id: '5x',
    nominalSpeedMultiplier: 5,
    leaderTStates: 1020,
    sync1TStates: 510,
    sync2TStates: 1020,
    payloadMiniSyncTStates: 1020,
    zeroTStates: 291,
    oneTStates: 571,
    expectedLeaderFrames: 14,
    expectedSync1Frames: 7,
    expectedSync2Frames: 14,
    expectedPayloadMiniSyncFrames: 14,
    expectedZeroFrames: 4,
    expectedOneFrames: 8,
    receiverLeaderMax: 26,
    receiverLeaderMin: 18,
    receiverSyncMin: 8,
    zeroMax: 9,
  );
  static const SnapshotTurboProfile speed4x = SnapshotTurboProfile(
    id: '4x',
    nominalSpeedMultiplier: 4,
    leaderTStates: 1239,
    sync1TStates: 619,
    sync2TStates: 1239,
    payloadMiniSyncTStates: 1239,
    zeroTStates: 331,
    oneTStates: 691,
    expectedLeaderFrames: 17,
    expectedSync1Frames: 9,
    expectedSync2Frames: 17,
    expectedPayloadMiniSyncFrames: 17,
    expectedZeroFrames: 5,
    expectedOneFrames: 10,
    receiverLeaderMax: 32,
    receiverLeaderMin: 23,
    receiverSyncMin: 11,
    zeroMax: 12,
  );
  static const SnapshotTurboProfile speed3x = SnapshotTurboProfile(
    id: '3x',
    nominalSpeedMultiplier: 3,
    leaderTStates: 1677,
    sync1TStates: 838,
    sync2TStates: 1677,
    payloadMiniSyncTStates: 1677,
    zeroTStates: 491,
    oneTStates: 1011,
    expectedLeaderFrames: 23,
    expectedSync1Frames: 12,
    expectedSync2Frames: 23,
    expectedPayloadMiniSyncFrames: 23,
    expectedZeroFrames: 7,
    expectedOneFrames: 14,
    receiverLeaderMax: 45,
    receiverLeaderMin: 32,
    receiverSyncMin: 16,
    zeroMax: 18,
  );
  static const SnapshotTurboProfile speed2_5x = SnapshotTurboProfile(
    id: '2.5x',
    nominalSpeedMultiplier: 2.5,
    leaderTStates: 2041,
    sync1TStates: 1020,
    sync2TStates: 2041,
    payloadMiniSyncTStates: 2041,
    zeroTStates: 571,
    oneTStates: 1211,
    expectedLeaderFrames: 28,
    expectedSync1Frames: 14,
    expectedSync2Frames: 28,
    expectedPayloadMiniSyncFrames: 28,
    expectedZeroFrames: 8,
    expectedOneFrames: 17,
    receiverLeaderMax: 55,
    receiverLeaderMin: 39,
    receiverSyncMin: 19,
    zeroMax: 21,
  );
  static const SnapshotTurboProfile speed2x = SnapshotTurboProfile(
    id: '2x',
    nominalSpeedMultiplier: 2,
    leaderTStates: 2552,
    sync1TStates: 1276,
    sync2TStates: 2552,
    payloadMiniSyncTStates: 2552,
    zeroTStates: 691,
    oneTStates: 1531,
    expectedLeaderFrames: 35,
    expectedSync1Frames: 18,
    expectedSync2Frames: 35,
    expectedPayloadMiniSyncFrames: 35,
    expectedZeroFrames: 10,
    expectedOneFrames: 21,
    receiverLeaderMax: 68,
    receiverLeaderMin: 49,
    receiverSyncMin: 25,
    zeroMax: 28,
  );
  static const SnapshotTurboProfile speed1x = SnapshotTurboProfile(
    id: '1x',
    nominalSpeedMultiplier: 1,
    leaderTStates: 5104,
    sync1TStates: 2552,
    sync2TStates: 5104,
    payloadMiniSyncTStates: 5104,
    zeroTStates: 1531,
    oneTStates: 2971,
    expectedLeaderFrames: 70,
    expectedSync1Frames: 35,
    expectedSync2Frames: 70,
    expectedPayloadMiniSyncFrames: 70,
    expectedZeroFrames: 21,
    expectedOneFrames: 41,
    receiverLeaderMax: 137,
    receiverLeaderMin: 100,
    receiverSyncMin: 51,
    zeroMax: 59,
  );
  static const List<SnapshotTurboProfile> values = [
    speed10x,
    speed7x,
    speed5x,
    speed4x,
    speed3x,
    speed2_5x,
    speed2x,
    speed1x,
  ];

  static const SnapshotTurboProfile defaultProfile = speed5x;

  static SnapshotTurboProfile resolve({
    required String id,
    required String catalogRevision,
  }) {
    validateProfiles(values);
    if (catalogRevision != SnapshotTurboProfiles.catalogRevision) {
      throw SnapshotException(
        SnapshotErrorCode.invalidTurboBlock,
        'Unknown snapshot turbo catalog revision "$catalogRevision"',
      );
    }
    for (final profile in values) {
      if (profile.id == id) return profile;
    }
    throw SnapshotException(
      SnapshotErrorCode.invalidTurboBlock,
      'Unknown snapshot turbo profile "$id"',
    );
  }

  static void validateProfiles(List<SnapshotTurboProfile> profiles) {
    const nominalOrder = [10.0, 7.0, 5.0, 4.0, 3.0, 2.5, 2.0, 1.0];
    if (SnapshotTiming.bitLoopMax <= 1 || SnapshotTiming.bitLoopMax > 0xff) {
      throw StateError('The receiver timeout must fit its nonzero byte patch');
    }
    if (profiles.length != nominalOrder.length) {
      throw ArgumentError.value(
        profiles,
        'profiles',
        'Expected eight profiles',
      );
    }
    final ids = <String>{};
    final fingerprints = <String>{};
    var previousRate = double.infinity;
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      if (profile.nominalSpeedMultiplier != nominalOrder[index]) {
        throw ArgumentError.value(
          profiles,
          'profiles',
          'Profiles must be ordered 10x, 7x, 5x, 4x, 3x, 2.5x, 2x, 1x',
        );
      }
      if (profile.id.isEmpty || !ids.add(profile.id)) {
        throw ArgumentError.value(profile.id, 'profile.id');
      }
      if (profile.zeroTStates <= 0 ||
          profile.oneTStates <= profile.zeroTStates ||
          profile.leaderTStates <= 0 ||
          profile.sync1TStates <= 0 ||
          profile.sync2TStates <= 0 ||
          profile.payloadMiniSyncTStates <= 0 ||
          profile.zeroMax <= 0 ||
          profile.zeroMax >= SnapshotTiming.bitLoopMax) {
        throw ArgumentError.value(profile, 'profile');
      }
      if (SnapshotTiming.framesForTStates(profile.leaderTStates) !=
              profile.expectedLeaderFrames ||
          SnapshotTiming.framesForTStates(profile.sync1TStates) !=
              profile.expectedSync1Frames ||
          SnapshotTiming.framesForTStates(profile.sync2TStates) !=
              profile.expectedSync2Frames ||
          SnapshotTiming.framesForTStates(profile.payloadMiniSyncTStates) !=
              profile.expectedPayloadMiniSyncFrames ||
          SnapshotTiming.framesForTStates(profile.zeroTStates) !=
              profile.expectedZeroFrames ||
          SnapshotTiming.framesForTStates(profile.oneTStates) !=
              profile.expectedOneFrames ||
          profile.sync1TStates != profile.leaderTStates ~/ 2 ||
          profile.expectedSync1Frames !=
              (profile.expectedLeaderFrames + 1) ~/ 2 ||
          profile.expectedSync1Frames >= profile.expectedLeaderFrames ||
          profile.expectedSync2Frames != profile.expectedLeaderFrames ||
          profile.expectedPayloadMiniSyncFrames !=
              profile.expectedLeaderFrames ||
          profile.expectedZeroFrames >= profile.expectedOneFrames) {
        throw ArgumentError.value(profile, 'profile', 'Frame mismatch');
      }
      if (profile.receiverSyncMin <= 0 ||
          profile.receiverSyncMin >= profile.receiverLeaderMin ||
          profile.receiverLeaderMin >= profile.receiverLeaderMax ||
          profile.receiverLeaderMax > 0xff ||
          profile.receiverLeaderMinCompare <= 0 ||
          profile.receiverLeaderMinCompare > 0xff ||
          profile.receiverSyncMinCompare <= 0 ||
          profile.receiverSyncMinCompare > 0xff ||
          !SnapshotAudioSampleRate.values.every(
            (sampleRate) =>
                SnapshotReceiverAcquisitionTimingSimulation.isSafe(
                  profile,
                  sampleRate: sampleRate,
                ) &&
                SnapshotReceiverAcquisitionTimingSimulation.isSafe(
                  profile,
                  sampleRate: sampleRate,
                  signalRatePermille:
                      SnapshotTiming.receiverAcquisitionMinRatePermille,
                ) &&
                SnapshotReceiverAcquisitionTimingSimulation.isSafe(
                  profile,
                  sampleRate: sampleRate,
                  signalRatePermille:
                      SnapshotTiming.receiverAcquisitionMaxRatePermille,
                ),
          )) {
        throw ArgumentError.value(
          profile,
          'profile',
          'Receiver acquisition timing is unsafe',
        );
      }
      for (final sampleRate in SnapshotAudioSampleRate.values) {
        final leaderFrames = profile.expectedLeaderFramesAt(sampleRate);
        final sync1Frames = profile.expectedSync1FramesAt(sampleRate);
        if (sync1Frames != (leaderFrames + 1) ~/ 2 ||
            sync1Frames >= leaderFrames ||
            profile.expectedSync2FramesAt(sampleRate) != leaderFrames ||
            profile.expectedPayloadMiniSyncFramesAt(sampleRate) !=
                leaderFrames ||
            profile.expectedZeroFramesAt(sampleRate) >=
                profile.expectedOneFramesAt(sampleRate) ||
            !SnapshotReceiverTimingSimulation.isSafe(
              profile,
              sampleRate: sampleRate,
            )) {
          throw ArgumentError.value(
            profile,
            'profile',
            'Timing is unsafe at ${sampleRate.label}',
          );
        }
      }
      if (!fingerprints.add(profile.timingFingerprint)) {
        throw ArgumentError.value(profile, 'profile', 'Duplicate timing');
      }
      if (profile.effectiveSpeedMultiplier >= previousRate) {
        throw ArgumentError.value(
          profile,
          'profile',
          'Effective rates must decrease',
        );
      }
      previousRate = profile.effectiveSpeedMultiplier;
    }
    if (!SnapshotAudioSampleRate.values.every(
      (sampleRate) =>
          SnapshotTiming.framesForTStates(
            SnapshotTiming.turboPreByteDelayTStates,
            sampleRate: sampleRate.hz,
          ) ==
          SnapshotTiming.preByteDelayFrames,
    )) {
      throw StateError('The fixed pre-byte delay must quantize to one frame');
    }
    if (SnapshotTiming.turboLeaderPulseCount.isOdd ||
        SnapshotTiming.turboLeaderPulseCount <
            SnapshotTiming.receiverLeaderMinimumEdges) {
      throw StateError('The fixed leader edge count is invalid');
    }
  }
}

/// Pure timing model of the receiver's 43-T leader/sync acquisition loops.
class SnapshotReceiverAcquisitionTimingSimulation {
  const SnapshotReceiverAcquisitionTimingSimulation._();

  static int? _pollIndex({
    required int frames,
    required int firstPollTStates,
    required int phaseTStates,
    required int signalRatePermille,
    required int sampleRate,
  }) {
    for (var poll = 0; poll < 0x100; poll++) {
      final observedAt =
          firstPollTStates +
          phaseTStates +
          poll * SnapshotTiming.receiverAcquisitionPollTStates;
      if (observedAt * sampleRate * signalRatePermille >=
          frames * SnapshotTiming.spectrumClock * 1000) {
        return poll;
      }
    }
    return null;
  }

  static bool isSafe(
    SnapshotTurboProfile profile, {
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
    int signalRatePermille = 1000,
  }) {
    if (signalRatePermille <= 0) {
      throw ArgumentError.value(signalRatePermille, 'signalRatePermille');
    }
    for (
      var phase = 0;
      phase < SnapshotTiming.receiverAcquisitionPollTStates;
      phase++
    ) {
      for (final firstPoll in [
        SnapshotTiming.receiverLeaderLoop1FirstPollTStates,
        SnapshotTiming.receiverLeaderLoop2FirstPollTStates,
      ]) {
        final leader = _pollIndex(
          frames: profile.expectedLeaderFramesAt(sampleRate),
          firstPollTStates: firstPoll,
          phaseTStates: phase,
          signalRatePermille: signalRatePermille,
          sampleRate: sampleRate.hz,
        );
        if (leader == null ||
            leader < profile.receiverLeaderMin - 1 ||
            leader >= profile.receiverLeaderMax) {
          return false;
        }
      }

      final sync = _pollIndex(
        frames: profile.expectedSync1FramesAt(sampleRate),
        firstPollTStates: SnapshotTiming.receiverLeaderLoop2FirstPollTStates,
        phaseTStates: phase,
        signalRatePermille: signalRatePermille,
        sampleRate: sampleRate.hz,
      );
      if (sync == null ||
          sync < profile.receiverSyncMin - 1 ||
          sync > profile.receiverLeaderMin - 2) {
        return false;
      }

      for (final miniSyncFrames in [
        profile.expectedSync2FramesAt(sampleRate),
        profile.expectedPayloadMiniSyncFramesAt(sampleRate),
      ]) {
        final miniSync = _pollIndex(
          frames: miniSyncFrames,
          firstPollTStates: SnapshotTiming.receiverMiniSyncFirstPollTStates,
          phaseTStates: phase,
          signalRatePermille: signalRatePermille,
          sampleRate: sampleRate.hz,
        );
        if (miniSync == null ||
            miniSync >= SnapshotTiming.receiverMiniSyncMax) {
          return false;
        }
      }
    }
    return true;
  }
}

/// Pure timing model of the receiver's inline data loop.
class SnapshotReceiverTimingSimulation {
  const SnapshotReceiverTimingSimulation._();

  static int? pollCount(
    SnapshotTurboProfile profile, {
    required bool one,
    required int phaseTStates,
    bool afterByteBoundary = false,
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
  }) {
    if (phaseTStates < 0 ||
        phaseTStates >= SnapshotTiming.receiverDataPollTStates) {
      throw ArgumentError.value(phaseTStates, 'phaseTStates');
    }
    final requested =
        (one ? profile.oneTStates : profile.zeroTStates) +
        (afterByteBoundary ? SnapshotTiming.turboPreByteDelayTStates : 0);
    final frames = SnapshotTiming.framesForTStates(
      requested,
      sampleRate: sampleRate.hz,
    );
    final firstPoll =
        SnapshotTiming.receiverFirstDataPollTStates +
        (afterByteBoundary ? SnapshotTiming.turboPreByteDelayTStates : 0) +
        phaseTStates;
    for (var poll = 1; poll <= SnapshotTiming.bitLoopMax; poll++) {
      final pollTStates =
          firstPoll + (poll - 1) * SnapshotTiming.receiverDataPollTStates;
      if (pollTStates * sampleRate.hz >=
          frames * SnapshotTiming.spectrumClock) {
        return poll;
      }
    }
    return null;
  }

  static bool isSafe(
    SnapshotTurboProfile profile, {
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
  }) {
    for (
      var phase = 0;
      phase < SnapshotTiming.receiverDataPollTStates;
      phase++
    ) {
      for (final afterBoundary in [false, true]) {
        final zero = pollCount(
          profile,
          one: false,
          phaseTStates: phase,
          afterByteBoundary: afterBoundary,
          sampleRate: sampleRate,
        );
        final one = pollCount(
          profile,
          one: true,
          phaseTStates: phase,
          afterByteBoundary: afterBoundary,
          sampleRate: sampleRate,
        );
        if (zero == null ||
            one == null ||
            zero > profile.zeroMax ||
            one <= profile.zeroMax) {
          return false;
        }
      }
    }
    return true;
  }
}
