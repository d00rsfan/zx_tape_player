import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_error.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_turbo_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('packaged receiver assets match the compatibility manifest', () async {
    final receiver48 = await _load(
      SnapshotReceiverManifest.receiver48.assetPath,
    );
    final receiver128 = await _load(
      SnapshotReceiverManifest.receiver128.assetPath,
    );
    final registers = await _load(SnapshotReceiverManifest.registerAssetPath);

    final bundle = SnapshotAssetBundle(
      receiver48Tap: receiver48,
      receiver128Tap: receiver128,
      registerBlob: registers,
    );
    expect(bundle.verify, returnsNormally);
  });

  test('all receiver patch addresses resolve inside the matching TAP', () {
    expect(
      SnapshotReceiverManifest.turboHeaderLength,
      SnapshotTurboHeader.byteLength,
    );
    for (final layout in [
      SnapshotReceiverManifest.receiver48,
      SnapshotReceiverManifest.receiver128,
    ]) {
      final addresses = [
        layout.copyStackPointerAddress,
        layout.copyDestinationAddress,
        layout.copySourceAddress,
        layout.copyInstructionAddress,
        layout.copyJumpAddress,
        layout.leaderMaxFirstAddress,
        layout.leaderMinCompareFirstAddress,
        layout.leaderMaxSecondAddress,
        layout.syncMinCompareAddress,
        layout.leaderMinCompareSecondAddress,
        layout.bitLoopMaxAddress,
        layout.miniSyncMaxAddress,
        layout.bitOneThresholdAddress,
        layout.ioInitAddress,
        layout.ioXorAddress,
      ];
      for (final address in addresses) {
        expect(
          layout.rawTapOffsetForAddress(address),
          inInclusiveRange(0, layout.length - 1),
        );
      }
      expect(
        layout.controlCodeStart + layout.controlCodeLength,
        layout.upperStartOffset,
      );
    }
    for (final entry in SnapshotReceiverManifest.registerOffsets.entries) {
      final width =
          entry.key == 'border' ||
              entry.key == 'r' ||
              entry.key == 'i' ||
              entry.key == 'interruptEnable'
          ? 1
          : 2;
      expect(
        entry.value + width,
        lessThanOrEqualTo(SnapshotReceiverManifest.registerLength),
      );
    }
  });

  test('asset verification rejects corruption', () async {
    final receiver48 = await _load(
      SnapshotReceiverManifest.receiver48.assetPath,
    );
    receiver48[receiver48.length - 1] ^= 1;
    expect(
      () => SnapshotReceiverManifest.verifyAsset(
        receiver48,
        expectedLength: SnapshotReceiverManifest.receiver48.length,
        expectedSha256: SnapshotReceiverManifest.receiver48.sha256,
        label: '48K receiver',
      ),
      throwsA(
        isA<SnapshotException>().having(
          (error) => error.code,
          'code',
          SnapshotErrorCode.invalidAsset,
        ),
      ),
    );
  });
}

Future<Uint8List> _load(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
