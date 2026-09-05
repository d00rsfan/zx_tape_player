import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_models.dart';

void main() {
  const registers = SnapshotRegisters(
    af: 1,
    bc: 2,
    de: 3,
    hl: 4,
    afAlt: 5,
    bcAlt: 6,
    deAlt: 7,
    hlAlt: 8,
    ix: 9,
    iy: 10,
    sp: 11,
    pc: 12,
    i: 13,
    r: 14,
    interruptMode: 1,
    interruptsEnabled: true,
    border: 2,
  );

  test('48K model owns banks and exposes fixed 5/2/0 memory view', () {
    final source = {
      0: Uint8List(SpectrumSnapshot.bankSize)
        ..fillRange(0, SpectrumSnapshot.bankSize, 0),
      2: Uint8List(SpectrumSnapshot.bankSize)
        ..fillRange(0, SpectrumSnapshot.bankSize, 2),
      5: Uint8List(SpectrumSnapshot.bankSize)
        ..fillRange(0, SpectrumSnapshot.bankSize, 5),
    };
    final snapshot = SpectrumSnapshot(
      format: SnapshotFormat.z80,
      machine: SpectrumSnapshotMachine.spectrum48k,
      registers: registers,
      banks: source,
    );
    source[5]![0] = 99;
    final returned = snapshot.bank(5)..[1] = 88;

    expect(snapshot.bank(5).take(2), [5, 5]);
    expect(returned.first, 5);
    expect(snapshot.fixed48kRam[0], 5);
    expect(snapshot.fixed48kRam[SpectrumSnapshot.bankSize], 2);
    expect(snapshot.fixed48kRam[2 * SpectrumSnapshot.bankSize], 0);
    expect(snapshot.registers.pc, 12);
  });

  test('128K model owns all banks and uses paged upper bank', () {
    final snapshot = SpectrumSnapshot(
      format: SnapshotFormat.sna,
      machine: SpectrumSnapshotMachine.spectrum128k,
      registers: registers,
      banks: {
        for (var bank = 0; bank < 8; bank++)
          bank: Uint8List(SpectrumSnapshot.bankSize)
            ..fillRange(0, SpectrumSnapshot.bankSize, bank),
      },
      lastOut7ffd: 3,
    );

    expect(snapshot.bankNumbers, {0, 1, 2, 3, 4, 5, 6, 7});
    expect(snapshot.fixed48kRam[0], 5);
    expect(snapshot.fixed48kRam[SpectrumSnapshot.bankSize], 2);
    expect(snapshot.fixed48kRam[2 * SpectrumSnapshot.bankSize], 3);
  });
}
