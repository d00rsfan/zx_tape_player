import 'dart:typed_data';

import 'package:zx_tape_player/snapshots/snapshot_models.dart';

enum SnapshotFixtureCategory {
  supported,
  unsupported,
  malformed,
  relocation,
  bankOrder,
  rle,
  checksum,
  edge,
  pcm,
}

class SnapshotFixtureMatrixCase {
  const SnapshotFixtureMatrixCase(this.id, this.category);

  final String id;
  final SnapshotFixtureCategory category;
}

/// Cross-layer cases required by the two snapshot capability specifications.
const snapshotFixtureMatrix = <SnapshotFixtureMatrixCase>[
  SnapshotFixtureMatrixCase(
    'z80-v1-raw-48k',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-v1-compressed-48k',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-v2-mode0-48k',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-v2-mode1-48k-interface1-unpaged',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-v2-mode3-128k',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-v3-mode0-48k',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-v3-mode4-128k',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase('sna-48k', SnapshotFixtureCategory.supported),
  SnapshotFixtureMatrixCase(
    'sna-128k-normal',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'sna-128k-current-bank2',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'sna-128k-current-bank5',
    SnapshotFixtureCategory.supported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-hardware-modes',
    SnapshotFixtureCategory.unsupported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-interface-rom',
    SnapshotFixtureCategory.unsupported,
  ),
  SnapshotFixtureMatrixCase('z80-mgt-rom', SnapshotFixtureCategory.unsupported),
  SnapshotFixtureMatrixCase(
    'z80-multiface-rom',
    SnapshotFixtureCategory.unsupported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-modified-hardware',
    SnapshotFixtureCategory.unsupported,
  ),
  SnapshotFixtureMatrixCase(
    'z80-nonzero-1ffd',
    SnapshotFixtureCategory.unsupported,
  ),
  SnapshotFixtureMatrixCase(
    'truncated-boundaries',
    SnapshotFixtureCategory.malformed,
  ),
  SnapshotFixtureMatrixCase(
    'oversized-rle-page',
    SnapshotFixtureCategory.malformed,
  ),
  SnapshotFixtureMatrixCase(
    'duplicate-missing-page',
    SnapshotFixtureCategory.malformed,
  ),
  SnapshotFixtureMatrixCase(
    'invalid-sna-stack',
    SnapshotFixtureCategory.malformed,
  ),
  SnapshotFixtureMatrixCase(
    'conflicting-sna-duplicate-bank',
    SnapshotFixtureCategory.malformed,
  ),
  SnapshotFixtureMatrixCase(
    'automatic-fixed-zero-run',
    SnapshotFixtureCategory.relocation,
  ),
  SnapshotFixtureMatrixCase(
    'live-receiver-zero-run',
    SnapshotFixtureCategory.relocation,
  ),
  SnapshotFixtureMatrixCase(
    'screen-fallback',
    SnapshotFixtureCategory.relocation,
  ),
  SnapshotFixtureMatrixCase(
    'pc-sp-im2-relocation-exclusions',
    SnapshotFixtureCategory.relocation,
  ),
  SnapshotFixtureMatrixCase(
    'unsafe-screen-fallback',
    SnapshotFixtureCategory.relocation,
  ),
  SnapshotFixtureMatrixCase(
    'all-current-128k-banks',
    SnapshotFixtureCategory.bankOrder,
  ),
  SnapshotFixtureMatrixCase(
    'final-7ffd-command',
    SnapshotFixtureCategory.bankOrder,
  ),
  SnapshotFixtureMatrixCase(
    'rle-empty-literal-runs',
    SnapshotFixtureCategory.rle,
  ),
  SnapshotFixtureMatrixCase('rle-escape-values', SnapshotFixtureCategory.rle),
  SnapshotFixtureMatrixCase('rle-final-run', SnapshotFixtureCategory.rle),
  SnapshotFixtureMatrixCase('rle-inline-overlap', SnapshotFixtureCategory.rle),
  SnapshotFixtureMatrixCase(
    'unsigned-high-bit-checksum',
    SnapshotFixtureCategory.checksum,
  ),
  SnapshotFixtureMatrixCase(
    'rom-bootstrap-edges',
    SnapshotFixtureCategory.edge,
  ),
  SnapshotFixtureMatrixCase(
    'turbo-one-edge-bits',
    SnapshotFixtureCategory.edge,
  ),
  SnapshotFixtureMatrixCase(
    'combined-byte-delay',
    SnapshotFixtureCategory.edge,
  ),
  SnapshotFixtureMatrixCase(
    'legacy-ceil-quantization',
    SnapshotFixtureCategory.pcm,
  ),
  SnapshotFixtureMatrixCase(
    'continuous-phase-pause',
    SnapshotFixtureCategory.pcm,
  ),
  SnapshotFixtureMatrixCase('deterministic-wav', SnapshotFixtureCategory.pcm),
];

const snapshotGolden48FallbackStarts = [0x4000, 0x5b00, 0xff38];
const snapshotGolden48FallbackLengths = [6912, 42040, 200];
const snapshotGoldenBootstrapFirstBlockFrames = 88781;
const snapshotGoldenTurboHeader = [
  0x34,
  0x12,
  0x78,
  0x56,
  0xbc,
  0x9a,
  1,
  0xde,
  0x00,
  0x04,
  0xf7,
  0x80,
  0x81,
  0x45,
  0x23,
  0xfe,
  0xff,
  0xef,
];

Uint8List makeZ80V1({
  bool compressed = false,
  int border = 3,
  bool rHigh = true,
  int interruptMode = 1,
  Uint8List? ram,
}) {
  final memory = ram ?? make48kRam();
  final header = _z80Header(
    pc: 0x4567,
    compressed: compressed,
    border: border,
    rHigh: rHigh,
    interruptMode: interruptMode,
  );
  final output = BytesBuilder(copy: false)..add(header);
  if (compressed) {
    output
      ..add(z80Compress(memory))
      ..add(const [0x00, 0xed, 0xed, 0x00]);
  } else {
    output.add(memory);
  }
  return output.takeBytes();
}

Uint8List makeZ80Extended({
  bool version3 = true,
  SpectrumSnapshotMachine machine = SpectrumSnapshotMachine.spectrum48k,
  bool compressedPages = false,
  int? hardwareMode,
  int lastOut7ffd = 0x03,
  bool modifiedHardware = false,
  int interfaceRomPaged = 0,
  int mgtRomPaged = 0,
  int multifaceRomPaged = 0,
  int lastOut1ffd = 0,
  Iterable<int>? pageOrder,
  Set<int> omittedPages = const {},
  List<int> duplicatePages = const [],
  Map<int, Uint8List> encodedPageOverrides = const {},
}) {
  final header = _z80Header(pc: 0, compressed: false);
  final extraLength = version3 ? 55 : 23;
  final extra = Uint8List(extraLength);
  _setU16(extra, 0, 0x4567);
  extra[2] =
      hardwareMode ??
      (version3
          ? machine == SpectrumSnapshotMachine.spectrum48k
                ? 0
                : 4
          : machine == SpectrumSnapshotMachine.spectrum48k
          ? 0
          : 3);
  extra[3] = lastOut7ffd;
  extra[4] = interfaceRomPaged;
  extra[5] = modifiedHardware ? 0x80 : 0;
  if (extraLength >= 28) extra[27] = mgtRomPaged;
  if (extraLength >= 29) extra[28] = multifaceRomPaged;
  if (extraLength == 55) extra[54] = lastOut1ffd;

  final required = machine == SpectrumSnapshotMachine.spectrum48k
      ? <int>[4, 5, 8]
      : <int>[3, 4, 5, 6, 7, 8, 9, 10];
  final ordered = pageOrder?.toList() ?? required;
  final output = BytesBuilder(copy: false)
    ..add(header)
    ..add([extraLength & 0xff, extraLength >> 8])
    ..add(extra);
  for (final page in [...ordered, ...duplicatePages]) {
    if (omittedPages.contains(page)) continue;
    final raw = Uint8List(SpectrumSnapshot.bankSize)
      ..fillRange(0, SpectrumSnapshot.bankSize, page);
    final override = encodedPageOverrides[page];
    if (override != null) {
      output
        ..add([override.length & 0xff, override.length >> 8, page])
        ..add(override);
    } else if (compressedPages) {
      final encoded = z80Compress(raw);
      output
        ..add([encoded.length & 0xff, encoded.length >> 8, page])
        ..add(encoded);
    } else {
      output
        ..add([0xff, 0xff, page])
        ..add(raw);
    }
  }
  return output.takeBytes();
}

Uint8List makeZ80PageWithLowLengthByteZero() {
  final output = BytesBuilder(copy: false);
  for (var i = 0; i < 64; i++) {
    output.add([0xed, 0xed, 252, 0x44]);
  }
  output.add(List.filled(256, 0x22));
  final result = output.takeBytes();
  assert(result.length == 512);
  return result;
}

Uint8List makeSna48({
  int sp = 0x8000,
  int pc = 0x4567,
  int border = 3,
  bool interruptsEnabled = true,
}) {
  final header = _snaHeader(
    sp: sp,
    border: border,
    interruptsEnabled: interruptsEnabled,
  );
  final ram = make48kRam();
  if (sp >= 0x4000 && sp <= 0xfffe) {
    final offset = sp - 0x4000;
    ram[offset] = pc & 0xff;
    ram[offset + 1] = pc >> 8;
  }
  return (BytesBuilder(copy: false)
        ..add(header)
        ..add(ram))
      .takeBytes();
}

Uint8List makeSna128({
  int currentBank = 0,
  int pc = 0x4500,
  int border = 3,
  bool interruptsEnabled = true,
  bool trDosPaged = false,
}) {
  final header = _snaHeader(
    sp: 0x9000,
    border: border,
    interruptsEnabled: interruptsEnabled,
  );
  final banks = {
    for (var bank = 0; bank < 8; bank++)
      bank: Uint8List(SpectrumSnapshot.bankSize)
        ..fillRange(0, SpectrumSnapshot.bankSize, bank),
  };
  final output = BytesBuilder(copy: false)
    ..add(header)
    ..add(banks[5]!)
    ..add(banks[2]!)
    ..add(banks[currentBank]!)
    ..add([pc & 0xff, pc >> 8, currentBank & 0x07, trDosPaged ? 1 : 0]);
  for (var bank = 0; bank < 8; bank++) {
    if (bank != 5 && bank != 2 && bank != currentBank) {
      output.add(banks[bank]!);
    }
  }
  return output.takeBytes();
}

Uint8List make48kRam() {
  final ram = Uint8List(3 * SpectrumSnapshot.bankSize);
  ram.fillRange(0, SpectrumSnapshot.bankSize, 5);
  ram.fillRange(SpectrumSnapshot.bankSize, 2 * SpectrumSnapshot.bankSize, 2);
  ram.fillRange(
    2 * SpectrumSnapshot.bankSize,
    3 * SpectrumSnapshot.bankSize,
    0,
  );
  return ram;
}

Uint8List z80Compress(Uint8List input) {
  final output = BytesBuilder(copy: false);
  var index = 0;
  while (index < input.length) {
    final value = input[index];
    var run = 1;
    while (index + run < input.length &&
        input[index + run] == value &&
        run < 255) {
      run++;
    }
    if (run >= 5 || value == 0xed && run >= 2) {
      output.add([0xed, 0xed, run, value]);
      index += run;
    } else {
      output.add(input.sublist(index, index + run));
      index += run;
    }
  }
  return output.takeBytes();
}

Uint8List _z80Header({
  required int pc,
  required bool compressed,
  int border = 3,
  bool rHigh = true,
  int interruptMode = 1,
}) {
  final header = Uint8List(30);
  header[0] = 0x12;
  header[1] = 0x34;
  _setU16(header, 2, 0x5678);
  _setU16(header, 4, 0x9abc);
  _setU16(header, 6, pc);
  _setU16(header, 8, 0x9000);
  header[10] = 0x3f;
  header[11] = 0x2a;
  header[12] = (rHigh ? 1 : 0) | ((border & 7) << 1) | (compressed ? 0x20 : 0);
  _setU16(header, 13, 0xdef0);
  _setU16(header, 15, 0x1112);
  _setU16(header, 17, 0x1314);
  _setU16(header, 19, 0x1516);
  header[21] = 0x17;
  header[22] = 0x18;
  _setU16(header, 23, 0x191a);
  _setU16(header, 25, 0x1b1c);
  header[27] = 1;
  header[28] = 1;
  header[29] = interruptMode;
  return header;
}

Uint8List _snaHeader({
  required int sp,
  required int border,
  required bool interruptsEnabled,
}) {
  final header = Uint8List(27);
  header[0] = 0x3f;
  _setU16(header, 1, 0x1516);
  _setU16(header, 3, 0x1314);
  _setU16(header, 5, 0x1112);
  header[7] = 0x18;
  header[8] = 0x17;
  _setU16(header, 9, 0x9abc);
  _setU16(header, 11, 0xdef0);
  _setU16(header, 13, 0x5678);
  _setU16(header, 15, 0x191a);
  _setU16(header, 17, 0x1b1c);
  header[19] = interruptsEnabled ? 0x04 : 0;
  header[20] = 0xaa;
  header[21] = 0x34;
  header[22] = 0x12;
  _setU16(header, 23, sp);
  header[25] = 1;
  header[26] = border;
  return header;
}

void _setU16(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}
