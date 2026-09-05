import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_converter.dart';
import 'package:zx_tape_player/snapshots/snapshot_models.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_restore_planner.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/snapshots/snapshot_turbo_codec.dart';

import 'snapshot_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const converter = SnapshotConverter();
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

  test('48K Z80 output restores RAM and complete normalized CPU state', () {
    final result = converter.convert(
      snapshotBytes: makeZ80V1(border: 6, rHigh: true, interruptMode: 2),
      fileName: 'semantic-48k.z80',
      assets: assets,
      turboProfile: SnapshotTurboProfiles.speed10x,
      invertPolarity: false,
    );

    final inspected = const _SnapshotStateHarness().inspect(result);

    expect(result.snapshot.machine, SpectrumSnapshotMachine.spectrum48k);
    expect(inspected.finalOut7ffd, isNull);
    _expectRegisters(
      inspected.registers,
      const SnapshotRegisters(
        af: 0x1234,
        bc: 0x5678,
        de: 0xdef0,
        hl: 0x9abc,
        afAlt: 0x1718,
        bcAlt: 0x1112,
        deAlt: 0x1314,
        hlAlt: 0x1516,
        ix: 0x1b1c,
        iy: 0x191a,
        sp: 0x9000,
        pc: 0x4567,
        i: 0x3f,
        r: 0xaa,
        interruptMode: 2,
        interruptsEnabled: true,
        border: 6,
      ),
    );
    expect(inspected.banks.keys, {0, 2, 5});
    expect(inspected.banks[0], everyElement(0));
    expect(inspected.banks[2], everyElement(2));
    expect(inspected.banks[5], everyElement(5));
    _expectWavProfile(result);
  });

  test('128K SNA output restores eight banks, CPU state, and full 0x7ffd', () {
    final fixture = makeSna128(
      currentBank: 3,
      pc: 0x4500,
      border: 5,
      interruptsEnabled: false,
      trDosPaged: true,
    );
    const pagingOffset = 27 + 3 * SpectrumSnapshot.bankSize + 2;
    fixture[pagingOffset] = 0x1b;

    final result = converter.convert(
      snapshotBytes: fixture,
      fileName: 'semantic-128k.sna',
      assets: assets,
      turboProfile: SnapshotTurboProfiles.speed10x,
      invertPolarity: false,
    );

    final inspected = const _SnapshotStateHarness().inspect(result);

    expect(result.snapshot.machine, SpectrumSnapshotMachine.spectrum128k);
    expect(inspected.finalOut7ffd, 0x1b);
    expect(
      result.snapshot.warnings.single.code,
      SnapshotWarningCode.trDosRomNotRestored,
    );
    _expectRegisters(
      inspected.registers,
      const SnapshotRegisters(
        af: 0x1234,
        bc: 0x5678,
        de: 0xdef0,
        hl: 0x9abc,
        afAlt: 0x1718,
        bcAlt: 0x1112,
        deAlt: 0x1314,
        hlAlt: 0x1516,
        ix: 0x1b1c,
        iy: 0x191a,
        sp: 0x9000,
        pc: 0x4500,
        i: 0x3f,
        r: 0xaa,
        interruptMode: 1,
        interruptsEnabled: false,
        border: 5,
      ),
    );
    expect(inspected.banks.keys, {0, 1, 2, 3, 4, 5, 6, 7});
    for (var bank = 0; bank < 8; bank++) {
      expect(inspected.banks[bank], everyElement(bank));
    }
    _expectWavProfile(result);
  });
}

class _InspectedSnapshotState {
  const _InspectedSnapshotState({
    required this.registers,
    required this.banks,
    required this.finalOut7ffd,
  });

  final SnapshotRegisters registers;
  final Map<int, Uint8List> banks;
  final int? finalOut7ffd;
}

/// Replays the state-bearing part of the pinned ZQLoader wire contract.
///
/// ROM bootstrap execution and the analog EAR path are intentionally outside
/// this harness. The receiver's temporary relocation/register-code footprint
/// is validated, then normalized back to the fixture bytes before comparing
/// the resumed snapshot state.
class _SnapshotStateHarness {
  const _SnapshotStateHarness();

  _InspectedSnapshotState inspect(SnapshotConversionResult result) {
    final snapshot = result.snapshot;
    final memory = <int, Uint8List>{
      for (final bank in snapshot.bankNumbers)
        bank: Uint8List(SpectrumSnapshot.bankSize),
    };
    final written = <int, Uint8List>{
      for (final bank in snapshot.bankNumbers)
        bank: Uint8List(SpectrumSnapshot.bankSize),
    };

    var selectedBank = 0;
    int? finalOut7ffd;
    for (final block in result.turboBlocks) {
      final payload = _decodePayload(block);
      final destination = block.header.destinationAddress == 0
          ? block.header.loadAddress
          : block.header.destinationAddress;
      if (block.targetBank != null && block.targetBank != selectedBank) {
        throw StateError(
          'Block ${block.name} targets bank ${block.targetBank}, but the '
          'preceding wire command selected bank $selectedBank',
        );
      }
      _writePayload(
        memory: memory,
        written: written,
        selectedBank: selectedBank,
        destination: destination,
        payload: payload,
      );

      if (block.header.action == SnapshotPostCommand.bankSwitch.wireValue) {
        finalOut7ffd = block.header.clearOrBank;
        selectedBank = finalOut7ffd & 0x07;
      }
    }

    final plan = result.restorePlan;
    final registerBytes = _readAddressRange(
      memory,
      plan.registerCodeStart,
      SnapshotReceiverManifest.registerLength,
    );
    final registerCoverage = _readAddressRange(
      written,
      plan.registerCodeStart,
      SnapshotReceiverManifest.registerLength,
    );
    if (registerCoverage.any((value) => value == 0)) {
      throw StateError('Register restoration code is absent from wire output');
    }
    final registers = _decodeRegisters(registerBytes);

    for (
      var address = SpectrumSnapshot.ramStart;
      address <= 0xffff;
      address++
    ) {
      final location = _fixedLocation(address);
      final expected = snapshot.bank(location.bank)[location.offset];
      final isRegisterCode =
          address >= plan.registerCodeStart &&
          address <
              plan.registerCodeStart + SnapshotReceiverManifest.registerLength;
      if (isRegisterCode) {
        memory[location.bank]![location.offset] = expected;
        continue;
      }
      if (written[location.bank]![location.offset] == 0) {
        final isRelocatedReceiver =
            !plan.usedScreenFallback &&
            address >= plan.loaderStart &&
            address < plan.loaderStart + plan.relocatedWorkingLength;
        if (!isRelocatedReceiver || expected != 0) {
          throw StateError(
            'Wire output omits non-scratch RAM at '
            '0x${address.toRadixString(16)}',
          );
        }
      }
    }

    for (final bank in snapshot.bankNumbers) {
      final expected = snapshot.bank(bank);
      final actual = memory[bank]!;
      for (var offset = 0; offset < SpectrumSnapshot.bankSize; offset++) {
        if (actual[offset] != expected[offset]) {
          throw StateError(
            'Restored RAM bank $bank differs at offset $offset: '
            '${actual[offset]} != ${expected[offset]}',
          );
        }
      }
    }

    if (result.turboBlocks.last.header.action != plan.registerCodeStart) {
      throw StateError('Final wire block does not execute register code');
    }
    if (snapshot.machine == SpectrumSnapshotMachine.spectrum48k) {
      if (finalOut7ffd != null) {
        throw StateError('48K output unexpectedly issues a paging command');
      }
    } else if (finalOut7ffd != snapshot.lastOut7ffd) {
      throw StateError(
        'Final 0x7ffd value $finalOut7ffd does not match '
        '${snapshot.lastOut7ffd}',
      );
    }

    return _InspectedSnapshotState(
      registers: registers,
      banks: Map.unmodifiable({
        for (final entry in memory.entries)
          entry.key: Uint8List.fromList(entry.value),
      }),
      finalOut7ffd: finalOut7ffd,
    );
  }

  Uint8List _decodePayload(SnapshotTurboBlock block) {
    if (!snapshotHeaderChecksumIsValid(block.headerBytes)) {
      throw StateError('Wire header checksum residue is not zero');
    }
    if (block.header.length != block.payload.length) {
      throw StateError('Wire payload length differs from its header');
    }
    if (snapshotPayloadChecksum(block.payload) !=
        block.header.payloadChecksum) {
      throw StateError('Wire payload checksum differs from its header');
    }
    final decoded = switch (block.header.compression) {
      SnapshotCompressionType.none => Uint8List.fromList(block.payload),
      SnapshotCompressionType.rle => const SnapshotRleCodec().decode(
        block.payload,
        SnapshotRleMetadata(
          codeForMost: block.header.codeForMost,
          codeForMultiples: block.header.codeForMultiples,
          valueForMost: block.header.valueForMost,
        ),
      ),
    };
    if (decoded.length != block.originalLength) {
      throw StateError('Decoded wire payload has the wrong length');
    }
    return decoded;
  }

  void _writePayload({
    required Map<int, Uint8List> memory,
    required Map<int, Uint8List> written,
    required int selectedBank,
    required int destination,
    required Uint8List payload,
  }) {
    for (var offset = 0; offset < payload.length; offset++) {
      final address = destination + offset;
      if (address < SpectrumSnapshot.ramStart || address > 0xffff) {
        throw StateError(
          'Wire payload writes outside Spectrum RAM at '
          '0x${address.toRadixString(16)}',
        );
      }
      final location = _location(address, selectedBank);
      final bankMemory = memory[location.bank];
      if (bankMemory == null) {
        throw StateError(
          'Wire payload selects absent RAM bank ${location.bank}',
        );
      }
      bankMemory[location.offset] = payload[offset];
      written[location.bank]![location.offset] = 1;
    }
  }

  Uint8List _readAddressRange(
    Map<int, Uint8List> memory,
    int start,
    int length,
  ) {
    final result = Uint8List(length);
    for (var offset = 0; offset < length; offset++) {
      final location = _fixedLocation(start + offset);
      result[offset] = memory[location.bank]![location.offset];
    }
    return result;
  }

  ({int bank, int offset}) _fixedLocation(int address) => _location(address, 0);

  ({int bank, int offset}) _location(int address, int selectedBank) {
    if (address < 0x8000) return (bank: 5, offset: address - 0x4000);
    if (address < 0xc000) return (bank: 2, offset: address - 0x8000);
    return (bank: selectedBank, offset: address - 0xc000);
  }

  SnapshotRegisters _decodeRegisters(Uint8List bytes) {
    final offsets = SnapshotReceiverManifest.registerOffsets;
    int byte(String name) => bytes[offsets[name]!];
    int word(String name) {
      final offset = offsets[name]!;
      return bytes[offset] | (bytes[offset + 1] << 8);
    }

    final interruptMode = switch (word('interruptMode')) {
      0x46ed => 0,
      0x56ed => 1,
      0x5eed => 2,
      final opcode => throw StateError(
        'Unknown interrupt-mode opcode 0x${opcode.toRadixString(16)}',
      ),
    };
    final interruptsEnabled = switch (byte('interruptEnable')) {
      0xfb => true,
      0xf3 => false,
      final opcode => throw StateError(
        'Unknown interrupt-enable opcode 0x${opcode.toRadixString(16)}',
      ),
    };

    return SnapshotRegisters(
      af: word('af'),
      bc: word('bc'),
      de: word('de'),
      hl: word('hl'),
      afAlt: word('afAlt'),
      bcAlt: word('bcAlt'),
      deAlt: word('deAlt'),
      hlAlt: word('hlAlt'),
      ix: word('ix'),
      iy: word('iy'),
      sp: word('sp'),
      pc: word('pc'),
      i: byte('i'),
      r: SnapshotRegisterPatcher.restoredRefreshRegister(byte('r')),
      interruptMode: interruptMode,
      interruptsEnabled: interruptsEnabled,
      border: byte('border'),
    );
  }
}

void _expectRegisters(SnapshotRegisters actual, SnapshotRegisters expected) {
  expect(
    [
      actual.af,
      actual.bc,
      actual.de,
      actual.hl,
      actual.afAlt,
      actual.bcAlt,
      actual.deAlt,
      actual.hlAlt,
      actual.ix,
      actual.iy,
      actual.sp,
      actual.pc,
      actual.i,
      actual.r,
      actual.interruptMode,
      actual.interruptsEnabled,
      actual.border,
    ],
    [
      expected.af,
      expected.bc,
      expected.de,
      expected.hl,
      expected.afAlt,
      expected.bcAlt,
      expected.deAlt,
      expected.hlAlt,
      expected.ix,
      expected.iy,
      expected.sp,
      expected.pc,
      expected.i,
      expected.r,
      expected.interruptMode,
      expected.interruptsEnabled,
      expected.border,
    ],
  );
}

void _expectWavProfile(SnapshotConversionResult result) {
  final wav = result.wav.wavBytes;
  int u16(int offset) => wav[offset] | (wav[offset + 1] << 8);
  int u32(int offset) => u16(offset) | (u16(offset + 2) << 16);

  expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
  expect(u16(22), 1);
  expect(u32(24), 48000);
  expect(u16(34), 8);
  expect(result.wav.blocks, hasLength(result.turboBlocks.length + 2));
  expect(result.wav.totalFrames, greaterThan(0));
}

Future<Uint8List> _asset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
