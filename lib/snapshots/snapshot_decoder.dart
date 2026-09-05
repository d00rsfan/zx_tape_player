import 'dart:typed_data';

import 'snapshot_byte_reader.dart';
import 'snapshot_error.dart';
import 'snapshot_models.dart';

class SnapshotDecoder {
  const SnapshotDecoder();

  SpectrumSnapshot decode(Uint8List bytes, String fileName) {
    if (bytes.isEmpty) {
      throw const SnapshotException(
        SnapshotErrorCode.emptyInput,
        'Snapshot file is empty',
        offset: 0,
      );
    }
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.z80')) {
      return _decodeZ80(bytes);
    }
    if (lowerName.endsWith('.sna')) {
      return _decodeSna(bytes);
    }
    throw SnapshotException(
      SnapshotErrorCode.invalidExtension,
      'Unsupported snapshot extension in "$fileName"',
    );
  }

  SpectrumSnapshot _decodeZ80(Uint8List bytes) {
    final reader = SnapshotByteReader(bytes, label: 'Z80 snapshot');
    final base = reader.readBytes(30);
    var flags = base[12];
    if (flags == 0xff) flags = 1;
    final basePc = _u16(base, 6);
    final r = (base[11] & 0x7f) | ((flags & 0x01) << 7);
    final iff1Enabled = base[27] != 0;
    final iff2Enabled = base[28] != 0;
    if (iff1Enabled != iff2Enabled) {
      throw const SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Distinct Z80 IFF1/IFF2 state cannot be restored by the snapshot receiver',
        offset: 27,
      );
    }

    if (basePc != 0) {
      if ((flags & 0x10) != 0) {
        throw const SnapshotException(
          SnapshotErrorCode.unsupportedHardware,
          'Z80 v1 SamRom state cannot be restored by the snapshot receiver',
          offset: 12,
        );
      }
      final ram = (flags & 0x20) != 0
          ? _decodeV1CompressedRam(reader)
          : reader.readBytes(3 * SpectrumSnapshot.bankSize);
      reader.expectEnd();
      return SpectrumSnapshot(
        format: SnapshotFormat.z80,
        machine: SpectrumSnapshotMachine.spectrum48k,
        registers: _z80Registers(base, pc: basePc, flags: flags, r: r),
        banks: _split48kRam(ram),
      );
    }

    final additionalLength = reader.readU16();
    final isV2 = additionalLength == 23;
    final isV3 = additionalLength == 54 || additionalLength == 55;
    if (!isV2 && !isV3) {
      throw SnapshotException(
        SnapshotErrorCode.invalidLength,
        'Unsupported Z80 additional header length $additionalLength',
        offset: 30,
      );
    }
    final extra = reader.readBytes(additionalLength);
    final pc = _u16(extra, 0);
    final hardwareMode = extra[2];
    final lastOut7ffd = extra[3];
    final interfaceRomPaged = extra[4];
    final emulationFlags = extra[5];

    // Z80 v2 mode 1 is a 48K machine with Interface 1 attached. The
    // attachment itself does not change the RAM page layout; byte 36 records
    // separately whether the Interface 1 ROM was actually paged, which is
    // rejected below because the receiver cannot restore that ROM mapping.
    final isRestorable48kMode =
        hardwareMode == 0 || (isV2 && hardwareMode == 1);
    final isRestorable128kMode =
        isV2 && hardwareMode == 3 || isV3 && hardwareMode == 4;

    late final SpectrumSnapshotMachine machine;
    if (isRestorable48kMode) {
      machine = SpectrumSnapshotMachine.spectrum48k;
    } else if (isRestorable128kMode) {
      machine = SpectrumSnapshotMachine.spectrum128k;
    } else {
      throw SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Z80 ${isV2 ? 'v2' : 'v3'} hardware mode $hardwareMode is not '
        'supported by the snapshot receiver',
        offset: 34,
      );
    }
    if (interfaceRomPaged != 0) {
      throw const SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Paged Interface 1 ROM state cannot be restored',
        offset: 36,
      );
    }
    if ((emulationFlags & 0x80) != 0) {
      throw const SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Modified Z80 hardware mode cannot be restored',
        offset: 37,
      );
    }
    if (additionalLength >= 28 && extra[27] != 0) {
      throw const SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Paged MGT ROM state cannot be restored',
        offset: 59,
      );
    }
    if (additionalLength >= 29 && extra[28] != 0) {
      throw const SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Paged Multiface ROM state cannot be restored',
        offset: 60,
      );
    }
    if (additionalLength == 55 && extra[54] != 0) {
      throw const SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Nonzero 0x1ffd paging state cannot be restored',
        offset: 86,
      );
    }

    final requiredPages = machine == SpectrumSnapshotMachine.spectrum48k
        ? const {4, 5, 8}
        : const {3, 4, 5, 6, 7, 8, 9, 10};
    final pages = <int, Uint8List>{};
    while (!reader.isAtEnd) {
      if (reader.remaining < 3) {
        throw SnapshotException(
          SnapshotErrorCode.truncatedInput,
          'Incomplete Z80 page header',
          offset: reader.offset,
        );
      }
      final compressedLength = reader.readU16();
      final page = reader.readU8();
      if (!requiredPages.contains(page)) {
        throw SnapshotException(
          SnapshotErrorCode.invalidPage,
          'Page $page is not valid for a ${machine == SpectrumSnapshotMachine.spectrum48k ? '48K' : '128K'} snapshot',
          offset: reader.offset - 1,
        );
      }
      if (pages.containsKey(page)) {
        throw SnapshotException(
          SnapshotErrorCode.duplicatePage,
          'Page $page appears more than once',
          offset: reader.offset - 1,
        );
      }
      final pageData = compressedLength == 0xffff
          ? reader.readBytes(SpectrumSnapshot.bankSize)
          : _decodePage(
              reader.readBytes(compressedLength),
              sourceOffset: reader.offset - compressedLength,
            );
      if (pageData.length != SpectrumSnapshot.bankSize) {
        throw SnapshotException(
          SnapshotErrorCode.invalidCompression,
          'Page $page decodes to ${pageData.length} bytes; expected '
          '${SpectrumSnapshot.bankSize}',
          offset: reader.offset,
        );
      }
      pages[page] = pageData;
    }
    final missing = requiredPages.difference(pages.keys.toSet()).toList()
      ..sort();
    if (missing.isNotEmpty) {
      throw SnapshotException(
        SnapshotErrorCode.missingPage,
        'Missing Z80 RAM page${missing.length == 1 ? '' : 's'}: '
        '${missing.join(', ')}',
      );
    }

    final banks = <int, Uint8List>{};
    if (machine == SpectrumSnapshotMachine.spectrum48k) {
      banks[2] = pages[4]!;
      banks[0] = pages[5]!;
      banks[5] = pages[8]!;
    } else {
      for (var page = 3; page <= 10; page++) {
        banks[page - 3] = pages[page]!;
      }
    }
    return SpectrumSnapshot(
      format: SnapshotFormat.z80,
      machine: machine,
      registers: _z80Registers(base, pc: pc, flags: flags, r: r),
      banks: banks,
      lastOut7ffd: machine == SpectrumSnapshotMachine.spectrum128k
          ? lastOut7ffd
          : null,
    );
  }

  SnapshotRegisters _z80Registers(
    Uint8List header, {
    required int pc,
    required int flags,
    required int r,
  }) {
    final interruptMode = header[29] & 0x03;
    _validateInterruptMode(interruptMode, 29);
    return SnapshotRegisters(
      af: (header[0] << 8) | header[1],
      bc: _u16(header, 2),
      de: _u16(header, 13),
      hl: _u16(header, 4),
      afAlt: (header[21] << 8) | header[22],
      bcAlt: _u16(header, 15),
      deAlt: _u16(header, 17),
      hlAlt: _u16(header, 19),
      ix: _u16(header, 25),
      iy: _u16(header, 23),
      sp: _u16(header, 8),
      pc: pc,
      i: header[10],
      r: r,
      interruptMode: interruptMode,
      interruptsEnabled: header[27] != 0,
      border: (flags >> 1) & 0x07,
    );
  }

  SpectrumSnapshot _decodeSna(Uint8List bytes) {
    const sna48Length = 27 + 3 * SpectrumSnapshot.bankSize;
    const sna128NormalLength = sna48Length + 4 + 5 * SpectrumSnapshot.bankSize;
    const sna128DuplicateLength =
        sna48Length + 4 + 6 * SpectrumSnapshot.bankSize;
    if (bytes.length != sna48Length &&
        bytes.length != sna128NormalLength &&
        bytes.length != sna128DuplicateLength) {
      throw SnapshotException(
        SnapshotErrorCode.invalidLength,
        'Unsupported SNA length ${bytes.length}; expected $sna48Length, '
        '$sna128NormalLength, or $sna128DuplicateLength',
      );
    }

    final reader = SnapshotByteReader(bytes, label: 'SNA snapshot');
    final header = reader.readBytes(27);
    final ram = reader.readBytes(3 * SpectrumSnapshot.bankSize);
    final interruptMode = header[25] & 0x03;
    _validateInterruptMode(interruptMode, 25);
    if (header[26] > 7) {
      throw SnapshotException(
        SnapshotErrorCode.invalidLength,
        'SNA border value ${header[26]} is outside 0-7',
        offset: 26,
      );
    }

    var sp = _u16(header, 23);
    late int pc;
    int? lastOut7ffd;
    final warnings = <SnapshotWarning>[];
    late Map<int, Uint8List> banks;
    if (bytes.length == sna48Length) {
      if (sp < SpectrumSnapshot.ramStart || sp > 0xfffe) {
        throw SnapshotException(
          SnapshotErrorCode.invalidStackPointer,
          '48K SNA stack pointer 0x${sp.toRadixString(16).padLeft(4, '0')} '
          'cannot provide a two-byte PC from RAM',
          offset: 23,
        );
      }
      final stackOffset = sp - SpectrumSnapshot.ramStart;
      pc = ram[stackOffset] | (ram[stackOffset + 1] << 8);
      sp = (sp + 2) & 0xffff;
      banks = _split48kRam(ram);
      reader.expectEnd();
    } else {
      pc = reader.readU16();
      lastOut7ffd = reader.readU8();
      final currentBank = lastOut7ffd & 0x07;
      final trDosPaged = reader.readU8();
      if (trDosPaged != 0) {
        warnings.add(
          const SnapshotWarning(
            SnapshotWarningCode.trDosRomNotRestored,
            'TR-DOS ROM paging state is present but cannot be restored',
          ),
        );
      }
      final bank5 = Uint8List.fromList(
        ram.sublist(0, SpectrumSnapshot.bankSize),
      );
      final bank2 = Uint8List.fromList(
        ram.sublist(SpectrumSnapshot.bankSize, 2 * SpectrumSnapshot.bankSize),
      );
      final currentBankBytes = Uint8List.fromList(
        ram.sublist(
          2 * SpectrumSnapshot.bankSize,
          3 * SpectrumSnapshot.bankSize,
        ),
      );
      final duplicatedFixedBank = currentBank == 5
          ? bank5
          : currentBank == 2
          ? bank2
          : null;
      if (duplicatedFixedBank != null &&
          !_bytesEqual(duplicatedFixedBank, currentBankBytes)) {
        throw SnapshotException(
          SnapshotErrorCode.invalidPage,
          '128K SNA contains conflicting copies of RAM bank $currentBank',
          offset: 27 + 2 * SpectrumSnapshot.bankSize,
        );
      }
      banks = {5: bank5, 2: bank2, currentBank: currentBankBytes};
      final remainingBanks = [
        for (var bank = 0; bank < 8; bank++)
          if (!banks.containsKey(bank)) bank,
      ];
      final expectedLength = remainingBanks.length == 5
          ? sna128NormalLength
          : sna128DuplicateLength;
      if (bytes.length != expectedLength) {
        throw SnapshotException(
          SnapshotErrorCode.invalidLength,
          'SNA current bank $currentBank requires length $expectedLength, '
          'not ${bytes.length}',
        );
      }
      for (final bank in remainingBanks) {
        banks[bank] = reader.readBytes(SpectrumSnapshot.bankSize);
      }
      reader.expectEnd();
    }

    return SpectrumSnapshot(
      format: SnapshotFormat.sna,
      machine: lastOut7ffd == null
          ? SpectrumSnapshotMachine.spectrum48k
          : SpectrumSnapshotMachine.spectrum128k,
      registers: SnapshotRegisters(
        af: (header[22] << 8) | header[21],
        bc: _u16(header, 13),
        de: _u16(header, 11),
        hl: _u16(header, 9),
        afAlt: (header[8] << 8) | header[7],
        bcAlt: _u16(header, 5),
        deAlt: _u16(header, 3),
        hlAlt: _u16(header, 1),
        ix: _u16(header, 17),
        iy: _u16(header, 15),
        sp: sp,
        pc: pc,
        i: header[0],
        r: header[20],
        interruptMode: interruptMode,
        interruptsEnabled: (header[19] & 0x04) != 0,
        border: header[26],
      ),
      banks: banks,
      lastOut7ffd: lastOut7ffd,
      warnings: warnings,
    );
  }

  Uint8List _decodeV1CompressedRam(SnapshotByteReader reader) {
    final output = <int>[];
    var foundTerminator = false;
    while (!reader.isAtEnd) {
      if (reader.remaining >= 4 &&
          reader.peekU8() == 0x00 &&
          reader.peekU8(1) == 0xed &&
          reader.peekU8(2) == 0xed &&
          reader.peekU8(3) == 0x00) {
        reader.skip(4);
        foundTerminator = true;
        break;
      }
      _decodeNextRleValue(reader, output);
      if (output.length > 3 * SpectrumSnapshot.bankSize) {
        throw SnapshotException(
          SnapshotErrorCode.invalidCompression,
          'Z80 v1 RAM expands beyond 48K',
          offset: reader.offset,
        );
      }
    }
    if (!foundTerminator) {
      throw SnapshotException(
        SnapshotErrorCode.invalidCompression,
        'Compressed Z80 v1 RAM has no end marker',
        offset: reader.offset,
      );
    }
    reader.expectEnd();
    if (output.length != 3 * SpectrumSnapshot.bankSize) {
      throw SnapshotException(
        SnapshotErrorCode.invalidCompression,
        'Z80 v1 RAM decodes to ${output.length} bytes; expected 49152',
        offset: reader.offset,
      );
    }
    return Uint8List.fromList(output);
  }

  Uint8List _decodePage(Uint8List compressed, {required int sourceOffset}) {
    if (compressed.isEmpty) {
      throw SnapshotException(
        SnapshotErrorCode.invalidCompression,
        'Compressed Z80 page is empty',
        offset: sourceOffset,
      );
    }
    final reader = SnapshotByteReader(compressed, label: 'compressed Z80 page');
    final output = <int>[];
    while (!reader.isAtEnd) {
      _decodeNextRleValue(reader, output, baseOffset: sourceOffset);
      if (output.length > SpectrumSnapshot.bankSize) {
        throw SnapshotException(
          SnapshotErrorCode.invalidCompression,
          'Compressed Z80 page expands beyond 16K',
          offset: sourceOffset + reader.offset,
        );
      }
    }
    return Uint8List.fromList(output);
  }

  void _decodeNextRleValue(
    SnapshotByteReader reader,
    List<int> output, {
    int baseOffset = 0,
  }) {
    final value = reader.readU8();
    if (value != 0xed || reader.isAtEnd || reader.peekU8() != 0xed) {
      output.add(value);
      return;
    }
    reader.readU8();
    if (reader.remaining < 2) {
      throw SnapshotException(
        SnapshotErrorCode.invalidCompression,
        'Truncated ED ED run',
        offset: baseOffset + reader.offset - 2,
      );
    }
    final count = reader.readU8();
    final repeated = reader.readU8();
    if (count == 0) {
      throw SnapshotException(
        SnapshotErrorCode.invalidCompression,
        'ED ED run has a zero repeat count',
        offset: baseOffset + reader.offset - 2,
      );
    }
    output.addAll(List.filled(count, repeated));
  }

  Map<int, Uint8List> _split48kRam(Uint8List ram) {
    if (ram.length != 3 * SpectrumSnapshot.bankSize) {
      throw SnapshotException(
        SnapshotErrorCode.invalidLength,
        '48K RAM contains ${ram.length} bytes',
      );
    }
    return {
      5: Uint8List.fromList(ram.sublist(0, SpectrumSnapshot.bankSize)),
      2: Uint8List.fromList(
        ram.sublist(SpectrumSnapshot.bankSize, 2 * SpectrumSnapshot.bankSize),
      ),
      0: Uint8List.fromList(
        ram.sublist(
          2 * SpectrumSnapshot.bankSize,
          3 * SpectrumSnapshot.bankSize,
        ),
      ),
    };
  }

  void _validateInterruptMode(int mode, int offset) {
    if (mode > 2) {
      throw SnapshotException(
        SnapshotErrorCode.unsupportedHardware,
        'Interrupt mode $mode is invalid',
        offset: offset,
      );
    }
  }

  int _u16(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
