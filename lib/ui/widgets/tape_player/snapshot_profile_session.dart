import 'package:zx_tape_player/snapshots/snapshot_timing.dart';

enum SnapshotProfileSwitchOutcome {
  committed,
  alreadyActive,
  rejectedConcurrent,
  failed,
}

class SnapshotProfileSwitchResult<T> {
  const SnapshotProfileSwitchResult._({
    required this.outcome,
    this.prepared,
    this.error,
    this.rollbackError,
  });

  final SnapshotProfileSwitchOutcome outcome;
  final T? prepared;
  final Object? error;
  final Object? rollbackError;

  bool get committed => outcome == SnapshotProfileSwitchOutcome.committed;
}

/// Owns player-session snapshot signal settings and the atomic switch boundary.
///
/// Preparation may create/cache output, but [activeProfile] and
/// [activeInvertPolarity]/[activeSampleRate] commit only after [bind] succeeds
/// and the optional
/// settings persistence callback completes. Any failure restores the prior
/// settings triple and invokes [rollback].
class SnapshotTurboProfileSession {
  SnapshotTurboProfileSession({
    SnapshotTurboProfile initialProfile = SnapshotTurboProfiles.defaultProfile,
    bool initialInvertPolarity = false,
    SnapshotAudioSampleRate initialSampleRate =
        SnapshotTiming.defaultSampleRate,
    Future<void> Function(
      SnapshotTurboProfile profile,
      bool invertPolarity,
      SnapshotAudioSampleRate sampleRate,
    )?
    persistCommittedSettings,
  }) : _activeProfile = _canonical(initialProfile),
       _activeInvertPolarity = initialInvertPolarity,
       _activeSampleRate = initialSampleRate,
       _persistCommittedSettings = persistCommittedSettings;

  SnapshotTurboProfile _activeProfile;
  bool _activeInvertPolarity;
  SnapshotAudioSampleRate _activeSampleRate;
  final Future<void> Function(
    SnapshotTurboProfile profile,
    bool invertPolarity,
    SnapshotAudioSampleRate sampleRate,
  )?
  _persistCommittedSettings;
  bool _preparing = false;

  SnapshotTurboProfile get activeProfile => _activeProfile;
  bool get activeInvertPolarity => _activeInvertPolarity;
  SnapshotAudioSampleRate get activeSampleRate => _activeSampleRate;
  bool get preparing => _preparing;

  Future<SnapshotProfileSwitchResult<T>> select<T>({
    required SnapshotTurboProfile requestedProfile,
    required bool requestedInvertPolarity,
    required SnapshotAudioSampleRate requestedSampleRate,
    required Future<void> Function() stopAndRewind,
    required Future<T> Function(
      SnapshotTurboProfile profile,
      bool invertPolarity,
      SnapshotAudioSampleRate sampleRate,
    )
    prepare,
    required Future<void> Function(T prepared) bind,
    required Future<void> Function() rollback,
  }) async {
    final target = _canonical(requestedProfile);
    if (_preparing) {
      return const SnapshotProfileSwitchResult._(
        outcome: SnapshotProfileSwitchOutcome.rejectedConcurrent,
      );
    }
    if (target == _activeProfile &&
        requestedInvertPolarity == _activeInvertPolarity &&
        requestedSampleRate == _activeSampleRate) {
      return const SnapshotProfileSwitchResult._(
        outcome: SnapshotProfileSwitchOutcome.alreadyActive,
      );
    }

    final previousProfile = _activeProfile;
    final previousInvertPolarity = _activeInvertPolarity;
    final previousSampleRate = _activeSampleRate;
    _preparing = true;
    T? prepared;
    try {
      await stopAndRewind();
      final value = await prepare(
        target,
        requestedInvertPolarity,
        requestedSampleRate,
      );
      prepared = value;
      await bind(value);
      _activeProfile = target;
      _activeInvertPolarity = requestedInvertPolarity;
      _activeSampleRate = requestedSampleRate;
      await _persistCommittedSettings?.call(
        target,
        requestedInvertPolarity,
        requestedSampleRate,
      );
      return SnapshotProfileSwitchResult._(
        outcome: SnapshotProfileSwitchOutcome.committed,
        prepared: prepared,
      );
    } catch (error) {
      _activeProfile = previousProfile;
      _activeInvertPolarity = previousInvertPolarity;
      _activeSampleRate = previousSampleRate;
      Object? rollbackError;
      try {
        await rollback();
      } catch (error) {
        rollbackError = error;
      }
      return SnapshotProfileSwitchResult._(
        outcome: SnapshotProfileSwitchOutcome.failed,
        prepared: prepared,
        error: error,
        rollbackError: rollbackError,
      );
    } finally {
      _preparing = false;
    }
  }

  static SnapshotTurboProfile _canonical(SnapshotTurboProfile profile) {
    final resolved = SnapshotTurboProfiles.resolve(
      id: profile.id,
      catalogRevision: SnapshotTurboProfiles.catalogRevision,
    );
    if (profile != resolved ||
        profile.nominalSpeedMultiplier != resolved.nominalSpeedMultiplier) {
      throw ArgumentError.value(profile, 'profile', 'Non-catalog timing');
    }
    return resolved;
  }
}
