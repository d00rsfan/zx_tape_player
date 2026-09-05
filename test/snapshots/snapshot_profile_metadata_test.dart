import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_converter.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';

import 'snapshot_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records representative 48K and 128K 5x/10x metadata', () async {
    final assets = SnapshotAssetBundle(
      receiver48Tap: await _asset(
        SnapshotReceiverManifest.receiver48.assetPath,
      ),
      receiver128Tap: await _asset(
        SnapshotReceiverManifest.receiver128.assetPath,
      ),
      registerBlob: await _asset(SnapshotReceiverManifest.registerAssetPath),
    );
    final fixtures = [
      ('48K Z80 v1', 'representative.z80', makeZ80V1()),
      ('128K SNA', 'representative.sna', makeSna128(currentBank: 3)),
    ];
    final records = <String>[];
    for (final fixture in fixtures) {
      final conversions = <String, SnapshotConversionResult>{};
      for (final profile in [
        SnapshotTurboProfiles.speed10x,
        SnapshotTurboProfiles.speed5x,
      ]) {
        final result = const SnapshotConverter().convert(
          snapshotBytes: fixture.$3,
          fileName: fixture.$2,
          assets: assets,
          turboProfile: profile,
          invertPolarity: false,
        );
        conversions[profile.id] = result;
        final bootstrapFrames = result.wav.blocks
            .take(2)
            .fold<int>(0, (sum, block) => sum + block.frameLength);
        final logical = BytesBuilder();
        for (final block in result.turboBlocks) {
          logical.add(block.headerBytes);
          logical.add(block.payload);
        }
        records.add(
          '${fixture.$1}|${profile.label}|${result.wav.totalFrames}|'
          '${result.wav.totalFrames - bootstrapFrames}|'
          '${result.turboBlocks.length}|${profile.bitOneThreshold}|'
          '${sha256.convert(logical.toBytes())}|'
          '${sha256.convert(result.wav.wavBytes)}',
        );
        final layout = SnapshotReceiverManifest.layoutFor(
          result.snapshot.machine,
        );
        expect(
          result.restorePlan.receiverTap[layout.rawTapOffsetForAddress(
            layout.bitOneThresholdAddress,
          )],
          profile.bitOneThreshold,
        );
      }

      final fast = conversions['10x']!;
      final slow = conversions['5x']!;
      final bootstrapFrames = fast.wav.blocks.first.frameLength;
      expect(
        slow.wav.wavBytes.sublist(44, 44 + bootstrapFrames),
        fast.wav.wavBytes.sublist(44, 44 + bootstrapFrames),
      );
      expect(
        slow.turboBlocks.map((block) => block.payload),
        fast.turboBlocks.map((block) => block.payload),
      );
    }

    expect(records, [
      '48K Z80 v1|10x|386830|119428|4|252|'
          'aa66c5f22a1c0b342eaa04d66aba290983d9aa49ebfad12f9bfb7335b8a38fef|'
          'f45816934b037da348f0d7861c63b544536daded1d8be9d544587df83b9bbabc',
      '48K Z80 v1|5x|450532|183210|4|246|'
          'aa66c5f22a1c0b342eaa04d66aba290983d9aa49ebfad12f9bfb7335b8a38fef|'
          '75d5ac4d2e7949ed39a22bbde12e7166d2c6991c75b3853a1bf77fa25130ce54',
      '128K SNA|10x|559871|289949|9|252|'
          '92a68c9a8752c318f7f875d1c166c98ee635b83b55b513b084bcb113ba210894|'
          '564e49fd0e56a611be6458ffae3ff1b42eb1abea0ea7a6a0e271e94d669361c7',
      '128K SNA|5x|708206|438404|9|246|'
          '92a68c9a8752c318f7f875d1c166c98ee635b83b55b513b084bcb113ba210894|'
          'e3f817297825cb818a2396fa8bbb17307b04e0dfec48cf33953bef2e8ddda10b',
    ]);
    expect(
      SnapshotTurboProfiles.speed5x.balancedByteFrames /
          SnapshotTurboProfiles.speed10x.balancedByteFrames,
      closeTo(1.96, 0.0001),
    );
  });
}

Future<Uint8List> _asset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
