import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_settings_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/snapshot_profile_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sessions without stored settings use 5x standard and retain commits',
    () async {
      final session = SnapshotTurboProfileSession();
      expect(session.activeProfile, SnapshotTurboProfiles.speed5x);
      expect(session.activeInvertPolarity, isFalse);
      expect(session.activeSampleRate, SnapshotAudioSampleRate.hz48k);

      final result = await session.select<String>(
        requestedProfile: SnapshotTurboProfiles.speed7x,
        requestedInvertPolarity: false,
        requestedSampleRate: SnapshotAudioSampleRate.hz48k,
        stopAndRewind: () async {},
        prepare: (profile, _, _) async => 'wav-${profile.id}',
        bind: (_) async {},
        rollback: () async {},
      );

      expect(result.committed, isTrue);
      expect(result.prepared, 'wav-7x');
      expect(session.activeProfile, SnapshotTurboProfiles.speed7x);
      expect(session.activeInvertPolarity, isFalse);
      expect(session.activeSampleRate, SnapshotAudioSampleRate.hz48k);
      expect(
        SnapshotTurboProfileSession().activeProfile,
        SnapshotTurboProfiles.speed5x,
      );
      expect(SnapshotTurboProfileSession().activeInvertPolarity, isFalse);
    },
  );

  test('already-active selection is a side-effect-free no-op', () async {
    final session = SnapshotTurboProfileSession();
    var calls = 0;
    final result = await session.select<void>(
      requestedProfile: SnapshotTurboProfiles.speed5x,
      requestedInvertPolarity: false,
      requestedSampleRate: SnapshotAudioSampleRate.hz48k,
      stopAndRewind: () async => calls++,
      prepare: (_, _, _) async => calls++,
      bind: (_) async => calls++,
      rollback: () async => calls++,
    );

    expect(result.outcome, SnapshotProfileSwitchOutcome.alreadyActive);
    expect(calls, 0);
  });

  test('serializes selection and commits only after binding', () async {
    final session = SnapshotTurboProfileSession();
    final prepareGate = Completer<void>();
    final calls = <String>[];

    final first = session.select<String>(
      requestedProfile: SnapshotTurboProfiles.speed10x,
      requestedInvertPolarity: true,
      requestedSampleRate: SnapshotAudioSampleRate.hz44_1k,
      stopAndRewind: () async => calls.add('stop'),
      prepare: (_, _, _) async {
        calls.add('prepare');
        await prepareGate.future;
        return 'fast.wav';
      },
      bind: (_) async {
        expect(session.activeProfile, SnapshotTurboProfiles.speed5x);
        expect(session.activeInvertPolarity, isFalse);
        expect(session.activeSampleRate, SnapshotAudioSampleRate.hz48k);
        calls.add('bind');
      },
      rollback: () async => calls.add('rollback'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(session.preparing, isTrue);

    final concurrent = await session.select<String>(
      requestedProfile: SnapshotTurboProfiles.speed2x,
      requestedInvertPolarity: false,
      requestedSampleRate: SnapshotAudioSampleRate.hz48k,
      stopAndRewind: () async => calls.add('unexpected'),
      prepare: (_, _, _) async => 'unexpected',
      bind: (_) async {},
      rollback: () async {},
    );
    expect(concurrent.outcome, SnapshotProfileSwitchOutcome.rejectedConcurrent);
    expect(calls, ['stop', 'prepare']);

    prepareGate.complete();
    expect((await first).committed, isTrue);
    expect(calls, ['stop', 'prepare', 'bind']);
    expect(session.activeProfile, SnapshotTurboProfiles.speed10x);
    expect(session.activeInvertPolarity, isTrue);
    expect(session.activeSampleRate, SnapshotAudioSampleRate.hz44_1k);
    expect(session.preparing, isFalse);
  });

  test('prepare and bind failures roll back without changing label', () async {
    for (final failDuringBind in [false, true]) {
      final persisted =
          <(SnapshotTurboProfile, bool, SnapshotAudioSampleRate)>[];
      final session = SnapshotTurboProfileSession(
        persistCommittedSettings: (profile, invertPolarity, sampleRate) async {
          persisted.add((profile, invertPolarity, sampleRate));
        },
      );
      final calls = <String>[];
      final result = await session.select<String>(
        requestedProfile: SnapshotTurboProfiles.speed4x,
        requestedInvertPolarity: true,
        requestedSampleRate: SnapshotAudioSampleRate.hz44_1k,
        stopAndRewind: () async => calls.add('stop'),
        prepare: (_, _, _) async {
          calls.add('prepare');
          if (!failDuringBind) throw StateError('conversion failed');
          return 'target.wav';
        },
        bind: (_) async {
          calls.add('bind');
          throw StateError('binding failed');
        },
        rollback: () async => calls.add('rollback'),
      );

      expect(result.outcome, SnapshotProfileSwitchOutcome.failed);
      expect(result.error, isA<StateError>());
      expect(session.activeProfile, SnapshotTurboProfiles.speed5x);
      expect(session.activeInvertPolarity, isFalse);
      expect(session.activeSampleRate, SnapshotAudioSampleRate.hz48k);
      expect(persisted, isEmpty);
      expect(calls.last, 'rollback');
    }
  });

  test(
    'hydrates and persists the complete settings triple after binding',
    () async {
      final persisted =
          <(SnapshotTurboProfile, bool, SnapshotAudioSampleRate)>[];
      late final SnapshotTurboProfileSession session;
      session = SnapshotTurboProfileSession(
        initialProfile: SnapshotTurboProfiles.speed2_5x,
        initialInvertPolarity: true,
        initialSampleRate: SnapshotAudioSampleRate.hz44_1k,
        persistCommittedSettings: (profile, invertPolarity, sampleRate) async {
          expect(session.activeProfile, profile);
          expect(session.activeInvertPolarity, invertPolarity);
          expect(session.activeSampleRate, sampleRate);
          persisted.add((profile, invertPolarity, sampleRate));
        },
      );
      expect(session.activeProfile, SnapshotTurboProfiles.speed2_5x);
      expect(session.activeInvertPolarity, isTrue);
      expect(session.activeSampleRate, SnapshotAudioSampleRate.hz44_1k);

      final result = await session.select<String>(
        requestedProfile: SnapshotTurboProfiles.speed2x,
        requestedInvertPolarity: false,
        requestedSampleRate: SnapshotAudioSampleRate.hz48k,
        stopAndRewind: () async {},
        prepare: (_, _, _) async => '2x-standard.wav',
        bind: (_) async => expect(persisted, isEmpty),
        rollback: () async {},
      );

      expect(result.committed, isTrue);
      expect(persisted, [
        (SnapshotTurboProfiles.speed2x, false, SnapshotAudioSampleRate.hz48k),
      ]);
      final restoredSession = SnapshotTurboProfileSession(
        initialProfile: persisted.single.$1,
        initialInvertPolarity: persisted.single.$2,
        initialSampleRate: persisted.single.$3,
      );
      expect(restoredSession.activeProfile, SnapshotTurboProfiles.speed2x);
      expect(restoredSession.activeInvertPolarity, isFalse);
      expect(restoredSession.activeSampleRate, SnapshotAudioSampleRate.hz48k);
    },
  );

  test('persistence failure restores prior settings and audio', () async {
    var rollbackCalls = 0;
    final session = SnapshotTurboProfileSession(
      initialProfile: SnapshotTurboProfiles.speed4x,
      initialInvertPolarity: true,
      initialSampleRate: SnapshotAudioSampleRate.hz44_1k,
      persistCommittedSettings: (_, _, _) async {
        throw StateError('storage failed');
      },
    );

    final result = await session.select<String>(
      requestedProfile: SnapshotTurboProfiles.speed3x,
      requestedInvertPolarity: false,
      requestedSampleRate: SnapshotAudioSampleRate.hz48k,
      stopAndRewind: () async {},
      prepare: (_, _, _) async => '3x-standard.wav',
      bind: (_) async {},
      rollback: () async => rollbackCalls++,
    );

    expect(result.outcome, SnapshotProfileSwitchOutcome.failed);
    expect(result.error, isA<StateError>());
    expect(session.activeProfile, SnapshotTurboProfiles.speed4x);
    expect(session.activeInvertPolarity, isTrue);
    expect(session.activeSampleRate, SnapshotAudioSampleRate.hz44_1k);
    expect(rollbackCalls, 1);
  });

  test('failed switch keeps the pair restored by the next session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = ZxSettingsService();
    await settings.load();
    const remembered = SnapshotSignalSettings(
      profile: SnapshotTurboProfiles.speed4x,
      invertPolarity: true,
      sampleRate: SnapshotAudioSampleRate.hz44_1k,
    );
    await settings.setSnapshotSignalSettings(remembered);
    final session = SnapshotTurboProfileSession(
      initialProfile: settings.snapshotSignalSettings.profile,
      initialInvertPolarity: settings.snapshotSignalSettings.invertPolarity,
      initialSampleRate: settings.snapshotSignalSettings.sampleRate,
      persistCommittedSettings: (profile, invertPolarity, sampleRate) =>
          settings.setSnapshotSignalSettings(
            SnapshotSignalSettings(
              profile: profile,
              invertPolarity: invertPolarity,
              sampleRate: sampleRate,
            ),
          ),
    );

    final failed = await session.select<String>(
      requestedProfile: SnapshotTurboProfiles.speed3x,
      requestedInvertPolarity: false,
      requestedSampleRate: SnapshotAudioSampleRate.hz48k,
      stopAndRewind: () async {},
      prepare: (_, _, _) async => '3x-standard.wav',
      bind: (_) async => throw StateError('binding failed'),
      rollback: () async {},
    );

    expect(failed.outcome, SnapshotProfileSwitchOutcome.failed);
    final afterFailure = ZxSettingsService();
    await afterFailure.load();
    expect(afterFailure.snapshotSignalSettings, remembered);

    final committed = await session.select<String>(
      requestedProfile: SnapshotTurboProfiles.speed2x,
      requestedInvertPolarity: false,
      requestedSampleRate: SnapshotAudioSampleRate.hz48k,
      stopAndRewind: () async {},
      prepare: (_, _, _) async => '2x-standard.wav',
      bind: (_) async {},
      rollback: () async {},
    );
    expect(committed.committed, isTrue);

    final nextAppSession = ZxSettingsService();
    await nextAppSession.load();
    expect(
      nextAppSession.snapshotSignalSettings,
      const SnapshotSignalSettings(
        profile: SnapshotTurboProfiles.speed2x,
        invertPolarity: false,
        sampleRate: SnapshotAudioSampleRate.hz48k,
      ),
    );
  });

  test('rejects a mutated profile even when its ID is known', () {
    final session = SnapshotTurboProfileSession();
    expect(
      () => session.select<void>(
        requestedProfile: SnapshotTurboProfiles.speed5x.copyWith(
          zeroTStates: 292,
        ),
        requestedInvertPolarity: false,
        requestedSampleRate: SnapshotAudioSampleRate.hz48k,
        stopAndRewind: () async {},
        prepare: (_, _, _) async {},
        bind: (_) async {},
        rollback: () async {},
      ),
      throwsArgumentError,
    );
  });

  test('polarity and sample rate are transactional settings changes', () async {
    final session = SnapshotTurboProfileSession();
    var preparedPolarity = false;
    var preparedSampleRate = SnapshotAudioSampleRate.hz48k;

    final result = await session.select<String>(
      requestedProfile: SnapshotTurboProfiles.speed5x,
      requestedInvertPolarity: true,
      requestedSampleRate: SnapshotAudioSampleRate.hz44_1k,
      stopAndRewind: () async {},
      prepare: (_, invertPolarity, sampleRate) async {
        preparedPolarity = invertPolarity;
        preparedSampleRate = sampleRate;
        return 'inverted.wav';
      },
      bind: (_) async {},
      rollback: () async {},
    );

    expect(result.committed, isTrue);
    expect(preparedPolarity, isTrue);
    expect(preparedSampleRate, SnapshotAudioSampleRate.hz44_1k);
    expect(session.activeProfile, SnapshotTurboProfiles.speed5x);
    expect(session.activeInvertPolarity, isTrue);
    expect(session.activeSampleRate, SnapshotAudioSampleRate.hz44_1k);
  });
}
