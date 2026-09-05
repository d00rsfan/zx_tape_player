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
          '${fixture.$1}|${profile.id}|${result.wav.totalFrames}|'
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
      '48K Z80 v1|10x|386925|119523|4|251|'
          'aa66c5f22a1c0b342eaa04d66aba290983d9aa49ebfad12f9bfb7335b8a38fef|'
          '7887e95120816ff397d31b575731bce29cdc79d69c13e8a2c6d16e97e7f83fb9',
      '48K Z80 v1|5x|450627|183305|4|246|'
          'aa66c5f22a1c0b342eaa04d66aba290983d9aa49ebfad12f9bfb7335b8a38fef|'
          'b882e4e23cb2073391a196c306a9d551ca9bb6c70636d74da734532b11827086',
      '128K SNA|10x|559926|290044|9|251|'
          '92a68c9a8752c318f7f875d1c166c98ee635b83b55b513b084bcb113ba210894|'
          '07f36a4552b9903f7dbf4fc37af18f0fdb9286b05d81721676792599b64183a4',
      '128K SNA|5x|708301|438499|9|246|'
          '92a68c9a8752c318f7f875d1c166c98ee635b83b55b513b084bcb113ba210894|'
          '0d34d3785d44a5b7eaaeb93f8d698e1d81f7df98a5b6dda8b2c5302f3f3a7840',
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
