import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/services/snapshot_asset_service.dart';
import 'package:zx_tape_player/services/snapshot_cache_service.dart';
import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/playback_policy.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/snapshot_profile_session.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

import '../snapshots/snapshot_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switches one snapshot through uncached and cached settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'snapshot_profile_workflow_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final image = resolveTapeImage((makeZ80V1(), 'state.z80'));
    final assets = await const SnapshotAssetLoader().load();
    const store = SnapshotCacheStore();
    final session = SnapshotTurboProfileSession();
    final player = _FakeSnapshotPlayer();
    var conversions = 0;

    Future<_PreparedProfile> prepare(
      SnapshotTurboProfile profile,
      bool invertPolarity,
      SnapshotAudioSampleRate sampleRate,
    ) async {
      final identity = SnapshotCacheIdentity.create(
        image,
        assets,
        turboProfile: profile,
        invertPolarity: invertPolarity,
        sampleRate: sampleRate,
      );
      final paths = store.paths(directory.path, identity);
      final entry = await store.getOrCreate(paths, identity, (
        outputPath,
      ) async {
        conversions++;
        final progress = ReceivePort();
        final subscription = progress.listen((_) {});
        try {
          return await convertTapeImage(
            TapeConversionRequest(
              image: image,
              outputPath: outputPath,
              progressPort: progress.sendPort,
              audioFilterIndex: AudioFilterType.none.index,
              snapshotAssets: assets,
              snapshotTurboProfileId: profile.id,
              snapshotTurboCatalogRevision:
                  SnapshotTurboProfiles.catalogRevision,
              snapshotInvertPolarity: invertPolarity,
              snapshotSampleRateHz: sampleRate.hz,
            ),
          );
        } finally {
          await subscription.cancel();
          progress.close();
        }
      });
      expect(entry.response.error, isNull);
      expect(entry.response.protocolMetadata?.turboProfileId, profile.id);
      expect(entry.response.protocolMetadata?.invertedPolarity, invertPolarity);
      expect(entry.response.protocolMetadata?.sampleRateHz, sampleRate.hz);
      expect(
        entry.response.protocolMetadata?.turboTimingFingerprint,
        profile.timingFingerprint,
      );
      expect(entry.response.blocks.first.sampleOffset, 0);
      expect(
        entry.response.blocks.every((block) => block.duration > Duration.zero),
        isTrue,
      );
      return _PreparedProfile(
        profile,
        invertPolarity,
        sampleRate,
        identity,
        paths,
        entry,
      );
    }

    final initial = await prepare(
      SnapshotTurboProfiles.speed5x,
      false,
      SnapshotAudioSampleRate.hz48k,
    );
    await player.bind(initial);
    expect(conversions, 1);
    player
      ..playing = true
      ..position = const Duration(seconds: 3);

    final cacheFlags = <bool>[];
    Future<SnapshotProfileSwitchResult<_PreparedProfile>> switchTo(
      SnapshotTurboProfile profile,
      bool invertPolarity,
      SnapshotAudioSampleRate sampleRate,
    ) async {
      final result = await session.select<_PreparedProfile>(
        requestedProfile: profile,
        requestedInvertPolarity: invertPolarity,
        requestedSampleRate: sampleRate,
        stopAndRewind: player.stopAndRewind,
        prepare: (profile, invertPolarity, sampleRate) async {
          final prepared = await prepare(profile, invertPolarity, sampleRate);
          cacheFlags.add(prepared.entry.fromCache);
          return prepared;
        },
        bind: player.bind,
        rollback: () => player.bind(initial),
      );
      expect(player.position, Duration.zero);
      expect(player.playing, isFalse);
      return result;
    }

    String key(
      SnapshotTurboProfile profile,
      bool invertPolarity,
      SnapshotAudioSampleRate sampleRate,
    ) => '${profile.id}:$invertPolarity:${sampleRate.hz}';
    final preparedBySettings = <String, _PreparedProfile>{
      key(initial.profile, initial.invertPolarity, initial.sampleRate): initial,
    };
    for (final profile in SnapshotTurboProfiles.values.where(
      (profile) => profile != SnapshotTurboProfiles.speed5x,
    )) {
      final result = await switchTo(
        profile,
        false,
        SnapshotAudioSampleRate.hz48k,
      );
      expect(result.committed, isTrue, reason: profile.label);
      preparedBySettings[key(profile, false, SnapshotAudioSampleRate.hz48k)] =
          result.prepared!;
    }
    for (final profile in SnapshotTurboProfiles.values) {
      final result = await switchTo(
        profile,
        true,
        SnapshotAudioSampleRate.hz48k,
      );
      expect(result.committed, isTrue, reason: '${profile.label} inverted');
      preparedBySettings[key(profile, true, SnapshotAudioSampleRate.hz48k)] =
          result.prepared!;
    }
    expect(conversions, SnapshotTurboProfiles.values.length * 2);
    expect(cacheFlags, everyElement(isFalse));

    for (final invertPolarity in [false, true]) {
      for (final profile in SnapshotTurboProfiles.values) {
        final cached = await switchTo(
          profile,
          invertPolarity,
          SnapshotAudioSampleRate.hz48k,
        );
        expect(cached.committed, isTrue, reason: profile.label);
        expect(
          cached.prepared!.paths.wavPath,
          preparedBySettings[key(
                profile,
                invertPolarity,
                SnapshotAudioSampleRate.hz48k,
              )]!
              .paths
              .wavPath,
        );
      }
    }

    final alternateRate = await switchTo(
      SnapshotTurboProfiles.speed1x,
      true,
      SnapshotAudioSampleRate.hz44_1k,
    );
    expect(alternateRate.committed, isTrue);
    expect(alternateRate.prepared!.entry.fromCache, isFalse);
    preparedBySettings[key(
          SnapshotTurboProfiles.speed1x,
          true,
          SnapshotAudioSampleRate.hz44_1k,
        )] =
        alternateRate.prepared!;
    final cachedDefaultRate = await switchTo(
      SnapshotTurboProfiles.speed1x,
      true,
      SnapshotAudioSampleRate.hz48k,
    );
    expect(cachedDefaultRate.committed, isTrue);
    expect(cachedDefaultRate.prepared!.entry.fromCache, isTrue);

    expect(conversions, SnapshotTurboProfiles.values.length * 2 + 1);
    expect(
      cacheFlags.where((fromCache) => fromCache).length,
      SnapshotTurboProfiles.values.length * 2 + 1,
    );
    expect(
      preparedBySettings.values.map((entry) => entry.paths.wavPath).toSet(),
      hasLength(SnapshotTurboProfiles.values.length * 2 + 1),
    );
    for (final prepared in preparedBySettings.values) {
      expect(await File(prepared.paths.sidecarPath).exists(), isTrue);
    }
    expect(player.playCalls, 0);
    expect(player.appliedSpeeds, everyElement(1.0));
    expect(player.appliedPitches, everyElement(1.0));
    expect(session.activeProfile, SnapshotTurboProfiles.speed1x);
    expect(session.activeInvertPolarity, isTrue);
    expect(session.activeSampleRate, SnapshotAudioSampleRate.hz48k);
  });
}

class _PreparedProfile {
  const _PreparedProfile(
    this.profile,
    this.invertPolarity,
    this.sampleRate,
    this.identity,
    this.paths,
    this.entry,
  );

  final SnapshotTurboProfile profile;
  final bool invertPolarity;
  final SnapshotAudioSampleRate sampleRate;
  final SnapshotCacheIdentity identity;
  final SnapshotCachePaths paths;
  final SnapshotCacheEntry entry;
}

class _FakeSnapshotPlayer {
  bool playing = false;
  Duration position = Duration.zero;
  String? wavPath;
  int playCalls = 0;
  final List<double> appliedSpeeds = [];
  final List<double> appliedPitches = [];

  Future<void> stopAndRewind() async {
    playing = false;
    position = Duration.zero;
  }

  Future<void> bind(_PreparedProfile prepared) async {
    await applyPlaybackRate(
      speed: 1.0,
      isAndroid: true,
      setSpeed: (speed) async => appliedSpeeds.add(speed),
      setPitch: (pitch) async => appliedPitches.add(pitch),
    );
    wavPath = prepared.entry.wavPath;
    position = Duration.zero;
    playing = false;
  }
}
