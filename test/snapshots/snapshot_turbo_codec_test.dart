import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_decoder.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_restore_planner.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/snapshots/snapshot_turbo_codec.dart';

import 'snapshot_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rle = SnapshotRleCodec();
  const encoder = SnapshotTurboStreamEncoder();
  const decoder = SnapshotDecoder();
  const planner = SnapshotRestorePlanner();
  late SnapshotAssetBundle assets;

  setUpAll(() async {
    assets = SnapshotAssetBundle(
      receiver48Tap: await _asset(
        SnapshotReceiverManifest.receiver48.assetPath,
      ),
      receiver128Tap: await _asset(
        SnapshotReceiverManifest.receiver128.assetPath,
      ),
      registerBlob: await _asset(SnapshotReceiverManifest.registerAssetPath),
    );
  });

  group('wire header and checksum', () {
    test('writes an 18-byte header with a zero checksum residue', () {
      const header = SnapshotTurboHeader(
        length: 0x1234,
        loadAddress: 0x5678,
        destinationAddress: 0x9abc,
        compression: SnapshotCompressionType.rle,
        payloadChecksum: 0xde,
        action: 0x0400,
        clearOrBank: 0x80f7,
        codeForMost: 0x81,
        decompressionCounter: 0x2345,
        codeForMultiples: 0xfe,
        valueForMost: 0xff,
      );

      expect(header.toBytes(), snapshotGoldenTurboHeader);
      expect(header.toBytes(), hasLength(SnapshotTurboHeader.byteLength));
      expect(snapshotHeaderChecksumIsValid(header.toBytes()), isTrue);
      final corrupted = Uint8List.fromList(header.toBytes())..[4] ^= 1;
      expect(snapshotHeaderChecksumIsValid(corrupted), isFalse);
      expect(snapshotPayloadChecksum(const [0x80, 0xff, 0x7f]), 0x07);
      expect(adjustDecompressionCounter(0), 0);
      expect(adjustDecompressionCounter(0x0100), 0x0100);
      expect(adjustDecompressionCounter(0x0101), 0x0201);
    });
  });

  group('receiver RLE', () {
    test('round trips empty, literal, repeated, and final-run data', () {
      final fixtures = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([9, 9, 9, 9]),
        Uint8List.fromList([...List.filled(10, 0), ...List.filled(4, 5), 7]),
      ];
      for (final fixture in fixtures) {
        final encoded = rle.encode(fixture);
        expect(rle.decode(encoded.payload, encoded.metadata), fixture);
      }

      final finalRun = rle.encode(Uint8List.fromList([9, 9, 9, 9]));
      expect(finalRun.metadata.valueForMost, 9);
      expect(finalRun.payload, [finalRun.metadata.codeForMost, 4]);
      expect(finalRun.decompressionCounter, 1);
    });

    test('escapes both codes and counts runs whose lengths equal a code', () {
      final allBytes = Uint8List.fromList(List.generate(256, (index) => index));
      final escaped = rle.encode(allBytes);
      expect(escaped.metadata.codeForMost, 255);
      expect(escaped.metadata.codeForMultiples, 254);
      expect(escaped.payload.length, 258);
      expect(rle.decode(escaped.payload, escaped.metadata), allBytes);

      final specialCount = Uint8List.fromList(List.filled(255, 7));
      final encoded = rle.encode(specialCount);
      expect(rle.decode(encoded.payload, encoded.metadata), specialCount);
      expect(encoded.decompressionCounter, 3);
    });

    test('keeps both escape codes and the most-run value distinct', () {
      final collision = <int>[
        0,
        0,
        0,
        for (var repetition = 0; repetition < 4; repetition++)
          for (var value = 1; value < 256; value++) value,
      ];
      final encoded = rle.encode(Uint8List.fromList(collision));

      expect({
        encoded.metadata.codeForMost,
        encoded.metadata.codeForMultiples,
        encoded.metadata.valueForMost,
      }, hasLength(3));
      expect(rle.decode(encoded.payload, encoded.metadata), collision);
    });

    test('round trips deterministic mixed property vectors', () {
      for (var seed = 0; seed < 32; seed++) {
        final data = Uint8List(1024);
        var state = seed + 1;
        for (var index = 0; index < data.length; index++) {
          state = (state * 1103515245 + 12345) & 0x7fffffff;
          data[index] = index % 29 < seed % 8 ? seed : state >> 16;
        }
        final encoded = rle.encode(data);
        expect(rle.decode(encoded.payload, encoded.metadata), data);
      }
    });

    test('rejects unsafe inline overlap and accepts safe expansion', () {
      final unsafe = Uint8List.fromList([
        ...List.filled(50, 42),
        for (var round = 0; round < 20; round++)
          for (var value = 0; value < 256; value++) value,
      ]);
      final candidate = rle.encode(unsafe);
      expect(candidate.payload.length, lessThan(unsafe.length));
      expect(rle.canDecodeInline(unsafe, candidate), isFalse);
      expect(rle.encodeInline(unsafe), isNull);

      final safe = Uint8List.fromList(List.filled(4096, 0x55));
      final inline = rle.encodeInline(safe);
      expect(inline, isNotNull);
      expect(rle.canDecodeInline(safe, inline!), isTrue);
      expect(rle.decode(inline.payload, inline.metadata), safe);
    });
  });

  group('restore plan encoding', () {
    test('48K stream matches commands, staging, checksums, and pauses', () {
      final ram = make48kRam()..fillRange(0, 48 * 1024, 0x33);
      final plan = planner.createPlan(
        decoder.decode(makeZ80V1(ram: ram), 'state.z80'),
        assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
      );
      final blocks = encoder.encode(plan);

      expect(blocks, hasLength(3));
      expect(blocks.map((block) => block.header.action), [
        SnapshotPostCommand.copyLoader.wireValue,
        SnapshotPostCommand.loadNext.wireValue,
        plan.registerCodeStart,
      ]);
      expect(blocks.map((block) => block.pauseBeforeMilliseconds), [
        100,
        153,
        883,
      ]);
      expect(blocks.last.header.loadAddress, plan.stagingAddress);
      expect(blocks.last.header.destinationAddress, plan.layout.upperStart);
      expect(
        blocks.last.header.compression,
        SnapshotCompressionType.none,
        reason: 'final copy overwrites the upper-resident RLE metadata',
      );
      _expectPayloadsRestorePlan(blocks, plan);
    });

    test('128K stream puts every paging command on the preceding block', () {
      final plan = planner.createPlan(
        decoder.decode(makeSna128(currentBank: 3), 'state.sna'),
        assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
      );
      final blocks = encoder.encode(plan);

      expect(blocks, hasLength(9));
      expect(blocks.map((block) => block.header.action), [
        SnapshotPostCommand.copyLoader.wireValue,
        SnapshotPostCommand.loadNext.wireValue,
        SnapshotPostCommand.bankSwitch.wireValue,
        SnapshotPostCommand.bankSwitch.wireValue,
        SnapshotPostCommand.bankSwitch.wireValue,
        SnapshotPostCommand.bankSwitch.wireValue,
        SnapshotPostCommand.bankSwitch.wireValue,
        SnapshotPostCommand.bankSwitch.wireValue,
        plan.registerCodeStart,
      ]);
      expect(blocks.skip(2).take(6).map((block) => block.header.clearOrBank), [
        1,
        3,
        4,
        6,
        7,
        3,
      ]);
      expect(blocks.last.header.loadAddress, plan.stagingAddress);
      expect(blocks.last.header.destinationAddress, 0xbf38);
      _expectPayloadsRestorePlan(blocks, plan);
    });

    test('restores all eight final 0x7ffd bank values', () {
      for (var bank = 0; bank < 8; bank++) {
        final plan = planner.createPlan(
          decoder.decode(makeSna128(currentBank: bank), 'bank$bank.sna'),
          assets,
          turboProfile: SnapshotTurboProfiles.speed10x,
        );
        final blocks = encoder.encode(plan);
        if (bank == 7) {
          expect(
            blocks[blocks.length - 2].header.action,
            SnapshotPostCommand.loadNext.wireValue,
          );
        } else {
          expect(
            blocks[blocks.length - 2].header.action,
            SnapshotPostCommand.bankSwitch.wireValue,
          );
          expect(blocks[blocks.length - 2].header.clearOrBank, bank);
        }
      }
    });
  });
}

void _expectPayloadsRestorePlan(
  List<SnapshotTurboBlock> blocks,
  SnapshotRestorePlan plan,
) {
  for (var index = 0; index < blocks.length; index++) {
    final block = blocks[index];
    final source = plan.blocks[index].data;
    expect(block.header.length, block.payload.length);
    expect(
      block.header.payloadChecksum,
      snapshotPayloadChecksum(block.payload),
    );
    if (block.header.compression == SnapshotCompressionType.rle) {
      final metadata = SnapshotRleMetadata(
        codeForMost: block.header.codeForMost,
        codeForMultiples: block.header.codeForMultiples,
        valueForMost: block.header.valueForMost,
      );
      expect(const SnapshotRleCodec().decode(block.payload, metadata), source);
    } else {
      expect(block.payload, source);
    }
  }
}

Future<Uint8List> _asset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
