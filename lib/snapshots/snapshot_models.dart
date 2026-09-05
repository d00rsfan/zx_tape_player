import 'dart:typed_data';

enum SpectrumSnapshotMachine { spectrum48k, spectrum128k }

enum SnapshotFormat { z80, sna }

enum SnapshotWarningCode { trDosRomNotRestored }

class SnapshotWarning {
  const SnapshotWarning(this.code, this.message);

  final SnapshotWarningCode code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is SnapshotWarning &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

class SnapshotRegisters {
  const SnapshotRegisters({
    required this.af,
    required this.bc,
    required this.de,
    required this.hl,
    required this.afAlt,
    required this.bcAlt,
    required this.deAlt,
    required this.hlAlt,
    required this.ix,
    required this.iy,
    required this.sp,
    required this.pc,
    required this.i,
    required this.r,
    required this.interruptMode,
    required this.interruptsEnabled,
    required this.border,
  });

  final int af;
  final int bc;
  final int de;
  final int hl;
  final int afAlt;
  final int bcAlt;
  final int deAlt;
  final int hlAlt;
  final int ix;
  final int iy;
  final int sp;
  final int pc;
  final int i;
  final int r;
  final int interruptMode;
  final bool interruptsEnabled;
  final int border;
}

class SpectrumSnapshot {
  SpectrumSnapshot({
    required this.format,
    required this.machine,
    required this.registers,
    required Map<int, Uint8List> banks,
    this.lastOut7ffd,
    List<SnapshotWarning> warnings = const [],
  }) : _banks = Map.unmodifiable({
         for (final entry in banks.entries)
           entry.key: Uint8List.fromList(entry.value),
       }),
       warnings = List.unmodifiable(warnings) {
    final expected = machine == SpectrumSnapshotMachine.spectrum48k
        ? const {0, 2, 5}
        : const {0, 1, 2, 3, 4, 5, 6, 7};
    if (_banks.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(_banks.keys.toSet()).isNotEmpty) {
      throw ArgumentError.value(_banks.keys, 'banks', 'Unexpected bank set');
    }
    for (final entry in _banks.entries) {
      if (entry.value.length != bankSize) {
        throw ArgumentError.value(
          entry.value.length,
          'bank ${entry.key}',
          'A Spectrum RAM bank must contain exactly $bankSize bytes',
        );
      }
    }
    if (machine == SpectrumSnapshotMachine.spectrum48k && lastOut7ffd != null) {
      throw ArgumentError('A 48K snapshot cannot contain a 0x7ffd value');
    }
    if (machine == SpectrumSnapshotMachine.spectrum128k &&
        lastOut7ffd == null) {
      throw ArgumentError('A 128K snapshot requires a 0x7ffd value');
    }
  }

  static const int bankSize = 16 * 1024;
  static const int ramStart = 0x4000;

  final SnapshotFormat format;
  final SpectrumSnapshotMachine machine;
  final SnapshotRegisters registers;
  final int? lastOut7ffd;
  final List<SnapshotWarning> warnings;
  final Map<int, Uint8List> _banks;

  Set<int> get bankNumbers => Set.unmodifiable(_banks.keys);

  Uint8List bank(int number) {
    final bytes = _banks[number];
    if (bytes == null) {
      throw ArgumentError.value(number, 'number', 'RAM bank is not present');
    }
    return Uint8List.fromList(bytes);
  }

  Uint8List get fixed48kRam {
    final result = Uint8List(3 * bankSize);
    result.setRange(0, bankSize, _banks[5]!);
    result.setRange(bankSize, 2 * bankSize, _banks[2]!);
    final upperBank = machine == SpectrumSnapshotMachine.spectrum48k
        ? 0
        : lastOut7ffd! & 0x07;
    result.setRange(2 * bankSize, 3 * bankSize, _banks[upperBank]!);
    return result;
  }
}
