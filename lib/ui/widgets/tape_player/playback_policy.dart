import 'package:zx_tape_player/services/tape_image_service.dart';

class TapePlaybackPolicy {
  const TapePlaybackPolicy(this.mediaKind);

  final TapeMediaKind? mediaKind;

  bool get isSnapshot => mediaKind == TapeMediaKind.snapshot;
  bool get refreshOnFilterChange => !isSnapshot;
  bool get canChangeSpeed => mediaKind == TapeMediaKind.tape;
  bool get canSelectSnapshotProfile => isSnapshot;
  bool get canSeekTimeline => !isSnapshot;
  bool get canNavigateBlocks => !isSnapshot;
  double effectiveSpeed(double tapeSpeed) => isSnapshot ? 1.0 : tapeSpeed;
}

class TapePlaybackSpeedCoordinator {
  TapePlaybackSpeedCoordinator({double initialTapeSpeed = 1.0})
    : _tapeSpeed = initialTapeSpeed;

  double _tapeSpeed;

  double get tapeSpeed => _tapeSpeed;

  Future<bool> select(
    double speed,
    TapePlaybackPolicy policy,
    Future<void> Function(double speed) apply,
  ) async {
    if (!policy.canChangeSpeed) return false;
    _tapeSpeed = speed;
    await apply(speed);
    return true;
  }

  Future<void> applyFor(
    TapePlaybackPolicy policy,
    Future<void> Function(double speed) apply,
  ) => apply(policy.effectiveSpeed(_tapeSpeed));
}

Future<void> applyPlaybackRate({
  required double speed,
  required bool isAndroid,
  required Future<void> Function(double speed) setSpeed,
  required Future<void> Function(double pitch) setPitch,
}) async {
  await setSpeed(speed);
  if (!isAndroid) return;
  try {
    await setPitch(speed);
  } catch (_) {
    // Some Android backends do not expose pitch control. Snapshot playback
    // still keeps the mandatory 1x speed in that case.
  }
}
