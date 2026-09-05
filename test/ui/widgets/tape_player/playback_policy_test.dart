import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/playback_policy.dart';

void main() {
  const tape = TapePlaybackPolicy(TapeMediaKind.tape);
  const snapshot = TapePlaybackPolicy(TapeMediaKind.snapshot);

  test('filter changes refresh tapes but leave snapshot audio untouched', () {
    expect(tape.refreshOnFilterChange, isTrue);
    expect(snapshot.refreshOnFilterChange, isFalse);
  });

  test('snapshot disables internal navigation while retaining restart', () {
    expect(tape.canSeekTimeline, isTrue);
    expect(tape.canNavigateBlocks, isTrue);
    expect(snapshot.canSeekTimeline, isFalse);
    expect(snapshot.canNavigateBlocks, isFalse);
  });

  test(
    'speed coordinator forces 1x and restores selected tape speed',
    () async {
      final coordinator = TapePlaybackSpeedCoordinator();
      final applied = <double>[];
      Future<void> apply(double speed) async => applied.add(speed);

      expect(await coordinator.select(2.25, tape, apply), isTrue);
      await coordinator.applyFor(snapshot, apply);
      expect(await coordinator.select(3.0, snapshot, apply), isFalse);
      await coordinator.applyFor(tape, apply);

      expect(coordinator.tapeSpeed, 2.25);
      expect(applied, <double>[2.25, 1.0, 2.25]);
    },
  );

  test('all snapshot profiles force Android speed and pitch to 1x', () async {
    final coordinator = TapePlaybackSpeedCoordinator();
    final speeds = <double>[];
    final pitches = <double>[];

    await coordinator.select(2.25, tape, (speed) async {});
    for (final profile in SnapshotTurboProfiles.values) {
      expect(profile.label, endsWith('x'));
      await coordinator.applyFor(
        snapshot,
        (speed) => applyPlaybackRate(
          speed: speed,
          isAndroid: true,
          setSpeed: (speed) async => speeds.add(speed),
          setPitch: (pitch) async => pitches.add(pitch),
        ),
      );
    }
    await coordinator.applyFor(
      tape,
      (speed) => applyPlaybackRate(
        speed: speed,
        isAndroid: true,
        setSpeed: (speed) async => speeds.add(speed),
        setPitch: (pitch) async => pitches.add(pitch),
      ),
    );

    expect(speeds.take(SnapshotTurboProfiles.values.length), everyElement(1.0));
    expect(
      pitches.take(SnapshotTurboProfiles.values.length),
      everyElement(1.0),
    );
    expect(speeds.last, 2.25);
    expect(pitches.last, 2.25);
    expect(coordinator.tapeSpeed, 2.25);
  });
}
