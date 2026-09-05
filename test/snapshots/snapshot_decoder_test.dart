import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_decoder.dart';
import 'package:zx_tape_player/snapshots/snapshot_error.dart';
import 'package:zx_tape_player/snapshots/snapshot_models.dart';

import 'snapshot_fixtures.dart';

void main() {
  const decoder = SnapshotDecoder();

  group('dispatch', () {
    test('accepts uppercase extensions and rejects empty/unknown input', () {
      expect(
        decoder.decode(makeZ80V1(), 'GAME.Z80').format,
        SnapshotFormat.z80,
      );
      expect(
        decoder.decode(makeSna48(), 'GAME.SNA').format,
        SnapshotFormat.sna,
      );
      expect(
        () => decoder.decode(Uint8List(0), 'empty.z80'),
        throwsCode(SnapshotErrorCode.emptyInput),
      );
      expect(
        () => decoder.decode(Uint8List.fromList([1]), 'game.tap'),
        throwsCode(SnapshotErrorCode.invalidExtension),
      );
    });
  });

  group('Z80 v1', () {
    test('decodes raw RAM without treating literal ED ED as RLE', () {
      final ram = make48kRam()
        ..[100] = 0xed
        ..[101] = 0xed
        ..[102] = 0x44;
      final snapshot = decoder.decode(
        makeZ80V1(compressed: false, ram: ram),
        'raw.z80',
      );

      expect(snapshot.machine, SpectrumSnapshotMachine.spectrum48k);
      expect(snapshot.fixed48kRam.sublist(100, 103), [0xed, 0xed, 0x44]);
      expect(snapshot.registers.pc, 0x4567);
      expect(snapshot.registers.r, 0xaa);
    });

    test('decodes compressed runs, a single ED, and an encoded ED pair', () {
      final ram = make48kRam()
        ..[100] = 0xed
        ..[101] = 0x44
        ..[102] = 0xed
        ..[103] = 0xed;
      final snapshot = decoder.decode(
        makeZ80V1(compressed: true, ram: ram),
        'compressed.z80',
      );

      expect(snapshot.fixed48kRam.sublist(100, 104), [0xed, 0x44, 0xed, 0xed]);
    });

    test('normalizes all border values and both R high-bit states', () {
      for (var border = 0; border < 8; border++) {
        for (final rHigh in [false, true]) {
          final snapshot = decoder.decode(
            makeZ80V1(border: border, rHigh: rHigh),
            'state.z80',
          );
          expect(snapshot.registers.border, border);
          expect(snapshot.registers.r, 0x2a | (rHigh ? 0x80 : 0));
        }
      }
    });

    test('rejects SamRom and distinct IFF1/IFF2 state', () {
      final samRom = Uint8List.fromList(makeZ80V1());
      samRom[12] |= 0x10;
      final mismatchedIff = Uint8List.fromList(makeZ80V1());
      mismatchedIff[28] = 0;

      for (final fixture in [samRom, mismatchedIff]) {
        expect(
          () => decoder.decode(fixture, 'unrestorable.z80'),
          throwsCode(SnapshotErrorCode.unsupportedHardware),
        );
      }
    });

    test('rejects wrong raw length, missing terminator, and trailing data', () {
      final raw = makeZ80V1();
      expect(
        () => decoder.decode(
          Uint8List.fromList(raw.sublist(0, raw.length - 1)),
          'bad.z80',
        ),
        throwsCode(SnapshotErrorCode.truncatedInput),
      );

      final compressed = makeZ80V1(compressed: true);
      expect(
        () => decoder.decode(
          Uint8List.fromList(compressed.sublist(0, compressed.length - 4)),
          'bad.z80',
        ),
        throwsCode(SnapshotErrorCode.invalidCompression),
      );
      expect(
        () => decoder.decode(Uint8List.fromList([...compressed, 1]), 'bad.z80'),
        throwsCode(SnapshotErrorCode.invalidLength),
      );
    });
  });

  group('Z80 v2/v3', () {
    test('decodes shuffled raw 48K pages with exact bank mapping', () {
      final snapshot = decoder.decode(
        makeZ80Extended(version3: false, pageOrder: const [8, 5, 4]),
        'v2.z80',
      );

      expect(snapshot.machine, SpectrumSnapshotMachine.spectrum48k);
      expect(snapshot.bank(5).first, 8);
      expect(snapshot.bank(2).first, 4);
      expect(snapshot.bank(0).first, 5);
      expect(snapshot.registers.pc, 0x4567);
    });

    test('decodes v2 mode 1 as 48K when Interface 1 ROM is not paged', () {
      for (final compressed in [false, true]) {
        final snapshot = decoder.decode(
          makeZ80Extended(
            version3: false,
            hardwareMode: 1,
            compressedPages: compressed,
            pageOrder: const [8, 5, 4],
          ),
          'v2-interface1.z80',
        );

        expect(snapshot.machine, SpectrumSnapshotMachine.spectrum48k);
        expect(snapshot.bank(5).first, 8);
        expect(snapshot.bank(2).first, 4);
        expect(snapshot.bank(0).first, 5);
        expect(snapshot.lastOut7ffd, isNull);
        expect(snapshot.warnings, isEmpty);
      }
    });

    test('rejects v2 mode 1 when Interface 1 ROM is paged', () {
      expect(
        () => decoder.decode(
          makeZ80Extended(
            version3: false,
            hardwareMode: 1,
            interfaceRomPaged: 0xff,
          ),
          'v2-interface1-rom.z80',
        ),
        throwsCode(SnapshotErrorCode.unsupportedHardware),
      );
    });

    test('decodes all compressed 128K pages', () {
      final snapshot = decoder.decode(
        makeZ80Extended(
          machine: SpectrumSnapshotMachine.spectrum128k,
          compressedPages: true,
          lastOut7ffd: 6,
        ),
        'v3.z80',
      );

      expect(snapshot.machine, SpectrumSnapshotMachine.spectrum128k);
      expect(snapshot.lastOut7ffd, 6);
      for (var bank = 0; bank < 8; bank++) {
        expect(snapshot.bank(bank).first, bank + 3);
      }
    });

    test('accepts a compressed page whose length low byte is zero', () {
      final snapshot = decoder.decode(
        makeZ80Extended(
          encodedPageOverrides: {4: makeZ80PageWithLowLengthByteZero()},
        ),
        'zero-length-byte.z80',
      );

      expect(snapshot.bank(2).first, 0x44);
      expect(snapshot.bank(2).last, 0x22);
    });

    test('rejects missing, duplicate, forbidden, and truncated pages', () {
      expect(
        () => decoder.decode(
          makeZ80Extended(omittedPages: const {5}),
          'missing.z80',
        ),
        throwsCode(SnapshotErrorCode.missingPage),
      );
      expect(
        () => decoder.decode(
          makeZ80Extended(duplicatePages: const [4]),
          'duplicate.z80',
        ),
        throwsCode(SnapshotErrorCode.duplicatePage),
      );
      expect(
        () => decoder.decode(
          makeZ80Extended(pageOrder: const [4, 5, 7]),
          'forbidden.z80',
        ),
        throwsCode(SnapshotErrorCode.invalidPage),
      );
      final valid = makeZ80Extended();
      expect(
        () => decoder.decode(
          Uint8List.fromList(valid.sublist(0, valid.length - 1)),
          'truncated.z80',
        ),
        throwsCode(SnapshotErrorCode.truncatedInput),
      );
    });

    test('rejects every unsupported hardware/peripheral state', () {
      final fixtures = [
        makeZ80Extended(version3: true, hardwareMode: 1),
        makeZ80Extended(hardwareMode: 2),
        makeZ80Extended(hardwareMode: 7),
        makeZ80Extended(interfaceRomPaged: 0xff),
        makeZ80Extended(modifiedHardware: true),
        makeZ80Extended(mgtRomPaged: 0xff),
        makeZ80Extended(multifaceRomPaged: 0xff),
        makeZ80Extended(lastOut1ffd: 1),
      ];
      for (final fixture in fixtures) {
        expect(
          () => decoder.decode(fixture, 'unsupported.z80'),
          throwsCode(SnapshotErrorCode.unsupportedHardware),
        );
      }

      for (final version3 in [false, true]) {
        final valid = makeZ80Extended(version3: version3);
        final admitted = version3 ? const {0, 4} : const {0, 1, 3};
        for (var mode = 0; mode <= 0xff; mode++) {
          if (admitted.contains(mode)) continue;
          final unsupported = Uint8List.fromList(valid)..[34] = mode;
          expect(
            () => decoder.decode(unsupported, 'mode-$mode.z80'),
            throwsCode(SnapshotErrorCode.unsupportedHardware),
          );
        }
      }
    });
  });

  group('SNA', () {
    test('decodes 48K stack PC, adjusted SP, border, and IFF2 bit', () {
      for (var border = 0; border < 8; border++) {
        for (final enabled in [false, true]) {
          final snapshot = decoder.decode(
            makeSna48(
              sp: 0xfffe,
              pc: 0x4500,
              border: border,
              interruptsEnabled: enabled,
            ),
            'state.sna',
          );
          expect(snapshot.registers.pc, 0x4500);
          expect(snapshot.registers.sp, 0);
          expect(snapshot.registers.border, border);
          expect(snapshot.registers.interruptsEnabled, enabled);
        }
      }
    });

    test('rejects invalid 48K stack pointers', () {
      for (final sp in [0, 0x3fff, 0xffff]) {
        expect(
          () => decoder.decode(makeSna48(sp: sp), 'bad-stack.sna'),
          throwsCode(SnapshotErrorCode.invalidStackPointer),
        );
      }
    });

    test('decodes normal and duplicated 128K current-bank layouts', () {
      final normal = decoder.decode(
        makeSna128(currentBank: 3, pc: 0x4500),
        'normal.sna',
      );
      final duplicate = decoder.decode(
        makeSna128(currentBank: 2, pc: 0x4500),
        'duplicate.sna',
      );

      expect(normal.lastOut7ffd, 3);
      expect(duplicate.lastOut7ffd, 2);
      expect(normal.bankNumbers, {0, 1, 2, 3, 4, 5, 6, 7});
      expect(duplicate.bankNumbers, {0, 1, 2, 3, 4, 5, 6, 7});
      for (var bank = 0; bank < 8; bank++) {
        expect(normal.bank(bank).first, bank);
        expect(duplicate.bank(bank).first, bank);
      }
    });

    test('rejects conflicting duplicate bank 2/5 copies in 128K SNA', () {
      for (final currentBank in [2, 5]) {
        final bytes = Uint8List.fromList(makeSna128(currentBank: currentBank));
        final duplicateOffset = 27 + 2 * SpectrumSnapshot.bankSize;
        bytes[duplicateOffset] ^= 0xff;
        expect(
          () => decoder.decode(bytes, 'conflicting-bank-$currentBank.sna'),
          throwsCode(SnapshotErrorCode.invalidPage),
        );
      }
    });

    test('retains a zero PC low byte and reports TR-DOS warning', () {
      final snapshot = decoder.decode(
        makeSna128(pc: 0x4500, trDosPaged: true),
        'trdos.sna',
      );

      expect(snapshot.registers.pc, 0x4500);
      expect(
        snapshot.warnings.single.code,
        SnapshotWarningCode.trDosRomNotRestored,
      );
    });

    test('rejects mismatched 128K layout and trailing garbage', () {
      final duplicate = makeSna128(currentBank: 2);
      expect(
        () => decoder.decode(
          Uint8List.fromList(
            duplicate.sublist(0, duplicate.length - SpectrumSnapshot.bankSize),
          ),
          'bad-layout.sna',
        ),
        throwsCode(SnapshotErrorCode.invalidLength),
      );
      expect(
        () => decoder.decode(
          Uint8List.fromList([...makeSna48(), 1]),
          'trailing.sna',
        ),
        throwsCode(SnapshotErrorCode.invalidLength),
      );
    });
  });

  group('robustness', () {
    test('structural truncations always produce typed failures', () {
      final fixtures = <(Uint8List, String, List<int>)>[
        (makeZ80V1(compressed: true), 'v1.z80', [0, 1, 29, 30, 31]),
        (makeZ80Extended(), 'v3.z80', [0, 29, 30, 31, 32, 86, 87, 88]),
        (makeSna48(), '48.sna', [0, 1, 26, 27, 28]),
        // 49179 is intentionally omitted: that prefix is itself a valid 48K
        // SNA and the format has no discriminator beyond total length.
        (makeSna128(), '128.sna', [0, 26, 27, 49178, 49180, 49182]),
      ];
      for (final (fixture, name, cuts) in fixtures) {
        for (final cut in cuts) {
          expect(
            () => decoder.decode(
              Uint8List.fromList(
                fixture.sublist(0, cut.clamp(0, fixture.length)),
              ),
              name,
            ),
            throwsA(isA<SnapshotException>()),
          );
        }
      }
    });

    test('oversized compressed page length is checked before allocation', () {
      final fixture = makeZ80Extended(compressedPages: true);
      const firstPageHeader = 30 + 2 + 55;
      fixture[firstPageHeader] = 0xfe;
      fixture[firstPageHeader + 1] = 0x7f;
      expect(
        () => decoder.decode(fixture, 'oversized.z80'),
        throwsCode(SnapshotErrorCode.truncatedInput),
      );
    });
  });
}

Matcher throwsCode(SnapshotErrorCode code) => throwsA(
  isA<SnapshotException>().having((error) => error.code, 'code', code),
);
