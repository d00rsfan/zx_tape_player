import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/services/snapshot_asset_service.dart';
import 'package:zx_tape_player/services/snapshot_cache_service.dart';
import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = SnapshotCacheStore();
  late Directory directory;
  late SnapshotCacheIdentity identity;
  late SnapshotCachePaths paths;
  late TapeConversionResponse response;
  late ResolvedTapeImage image;
  late SnapshotAssetBundle assets;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('snapshot_cache_test_');
    image = resolveTapeImage((Uint8List.fromList([1, 2, 3]), 'state.z80'));
    assets = await const SnapshotAssetLoader().load();
    identity = SnapshotCacheIdentity.create(
      image,
      assets,
      turboProfile: SnapshotTurboProfiles.defaultProfile,
      invertPolarity: false,
    );
    paths = store.paths(directory.path, identity);
    response = _response(identity);
    await File(paths.wavPath).writeAsBytes(_wav(), flush: true);
    await store.write(paths, identity, response);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'restores blocks, warnings, protocol, and offsets from a valid hit',
    () async {
      final hit = await store.read(paths, identity);

      expect(hit, isNotNull);
      expect(hit!.wavPath, paths.wavPath);
      expect(hit.response.mediaKind, TapeMediaKind.snapshot);
      expect(hit.response.blocks.single.title, 'Snapshot bootstrap');
      expect(hit.response.blocks.single.sampleOffset, 12);
      expect(
        hit.response.blocks.single.timeOffset,
        const Duration(microseconds: 250),
      );
      expect(
        hit.response.blocks.single.duration,
        const Duration(microseconds: 500),
      );
      expect(hit.response.warnings.single.code, 'trDosRomNotRestored');
      expect(
        hit.response.protocolMetadata?.protocolVersion,
        identity.protocolVersion,
      );
      expect(
        hit.response.protocolMetadata?.turboProfileId,
        SnapshotTurboProfiles.defaultProfile.id,
      );
      expect(hit.response.protocolMetadata?.invertedPolarity, isFalse);
      expect(hit.response.protocolMetadata?.sampleRateHz, 48000);
    },
  );

  test(
    'player-style preparation reuses cache across store recreation',
    () async {
      var conversions = 0;
      const recreatedStore = SnapshotCacheStore();

      final entry = await recreatedStore.getOrCreate(paths, identity, (
        _,
      ) async {
        conversions++;
        return response;
      });

      expect(entry.fromCache, isTrue);
      expect(conversions, 0);
      expect(entry.response.blocks.single.sampleOffset, 12);
      expect(entry.response.warnings.single.code, 'trDosRomNotRestored');
    },
  );

  test(
    'identity excludes tape filters and changes for every compatibility input',
    () async {
      final sameAcrossAnyFilter = identity;
      expect(sameAcrossAnyFilter.digest, identity.digest);
      expect(await store.read(paths, sameAcrossAnyFilter), isNotNull);

      final mismatches = [
        identity.copyWith(sourceSha256: 'changed-source'),
        identity.copyWith(sourceFileName: 'other.zip'),
        identity.copyWith(selectedInnerName: 'other/state.z80'),
        identity.copyWith(protocolVersion: 'next-protocol'),
        identity.copyWith(receiver48Sha256: 'changed-48-asset'),
        identity.copyWith(receiver128Sha256: 'changed-128-asset'),
        identity.copyWith(registerSha256: 'changed-register-asset'),
        identity.copyWith(wavProfile: 'different-wav-profile'),
        identity.copyWith(turboProfileId: '10x'),
        identity.copyWith(turboCatalogRevision: 'next-catalog'),
        identity.copyWith(turboTimingFingerprint: 'different-timing'),
        identity.copyWith(invertedPolarity: true),
        identity.copyWith(sampleRateHz: 44100),
      ];
      for (final mismatch in mismatches) {
        expect(await store.read(paths, mismatch), isNull);
        expect(mismatch.digest, isNot(identity.digest));
      }
    },
  );

  test('rejects WAV corruption and sidecar corruption', () async {
    final wavFile = File(paths.wavPath);
    final corruptedWav = await wavFile.readAsBytes()
      ..[44] ^= 0xff;
    await wavFile.writeAsBytes(corruptedWav, flush: true);
    expect(await store.read(paths, identity), isNull);

    await wavFile.writeAsBytes(_wav(), flush: true);
    await store.write(paths, identity, response);
    final sidecarFile = File(paths.sidecarPath);
    final sidecar =
        jsonDecode(await sidecarFile.readAsString()) as Map<String, dynamic>;
    (sidecar['protocol'] as Map<String, dynamic>)['protocolVersion'] =
        'corrupted';
    await sidecarFile.writeAsString(jsonEncode(sidecar), flush: true);
    expect(await store.read(paths, identity), isNull);

    await store.write(paths, identity, response);
    await sidecarFile.writeAsString('{broken', flush: true);
    expect(await store.read(paths, identity), isNull);
  });

  test(
    'profile entries coexist, hit identically, and legacy sidecars miss',
    () async {
      final fastIdentity = SnapshotCacheIdentity.create(
        image,
        assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
        invertPolarity: false,
      );
      final fastPaths = store.paths(directory.path, fastIdentity);
      expect(fastPaths.wavPath, isNot(paths.wavPath));
      expect(await store.read(fastPaths, fastIdentity), isNull);

      await File(fastPaths.wavPath).writeAsBytes(_wav(), flush: true);
      await store.write(fastPaths, fastIdentity, _response(fastIdentity));
      expect(await store.read(fastPaths, fastIdentity), isNotNull);
      expect(await store.read(paths, identity), isNotNull);

      final identical = SnapshotCacheIdentity.create(
        image,
        assets,
        turboProfile: SnapshotTurboProfiles.defaultProfile,
        invertPolarity: false,
      );
      expect(identical.digest, identity.digest);
      expect(await store.read(paths, identical), isNotNull);

      final inverted = SnapshotCacheIdentity.create(
        image,
        assets,
        turboProfile: SnapshotTurboProfiles.defaultProfile,
        invertPolarity: true,
      );
      expect(inverted.digest, isNot(identity.digest));
      expect(
        await store.read(store.paths(directory.path, inverted), inverted),
        isNull,
      );

      final alternateRate = SnapshotCacheIdentity.create(
        image,
        assets,
        turboProfile: SnapshotTurboProfiles.defaultProfile,
        invertPolarity: false,
        sampleRate: SnapshotAudioSampleRate.hz44_1k,
      );
      expect(alternateRate.digest, isNot(identity.digest));
      expect(alternateRate.wavProfile, contains('44100hz'));

      final sidecarFile = File(paths.sidecarPath);
      final legacy =
          jsonDecode(await sidecarFile.readAsString()) as Map<String, dynamic>;
      legacy['version'] = 2;
      (legacy['identity'] as Map<String, dynamic>).remove('invertedPolarity');
      (legacy['protocol'] as Map<String, dynamic>).remove('invertedPolarity');
      await sidecarFile.writeAsString(jsonEncode(legacy), flush: true);
      expect(await store.read(paths, identity), isNull);
    },
  );
}

TapeConversionResponse _response(SnapshotCacheIdentity identity) =>
    TapeConversionResponse(
      mediaKind: TapeMediaKind.snapshot,
      blocks: [
        TapeBlockInfo(
          index: 0,
          typeName: 'Snapshot',
          title: 'Snapshot bootstrap',
          isHeader: true,
          sampleOffset: 12,
          timeOffset: const Duration(microseconds: 250),
          duration: const Duration(microseconds: 500),
        ),
      ],
      warnings: const [
        TapeConversionMessage(
          code: 'trDosRomNotRestored',
          message: 'TR-DOS is not restored',
        ),
      ],
      protocolMetadata: SnapshotProtocolMetadata(
        protocolVersion: identity.protocolVersion,
        receiverSha256: identity.receiver48Sha256,
        registerSha256: identity.registerSha256,
        wavProfile: identity.wavProfile,
        turboProfileId: identity.turboProfileId,
        turboCatalogRevision: identity.turboCatalogRevision,
        turboTimingFingerprint: identity.turboTimingFingerprint,
        invertedPolarity: identity.invertedPolarity,
        sampleRateHz: identity.sampleRateHz,
      ),
    );

Uint8List _wav() {
  final wav = Uint8List(46);
  final data = ByteData.sublistView(wav);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      wav[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 38, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 48000, Endian.little);
  data.setUint32(28, 48000, Endian.little);
  data.setUint16(32, 1, Endian.little);
  data.setUint16(34, 8, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, 1, Endian.little);
  wav[44] = 128;
  wav[45] = 0;
  return wav;
}
