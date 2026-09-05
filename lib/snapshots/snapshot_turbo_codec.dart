import 'dart:typed_data';

import 'snapshot_error.dart';
import 'snapshot_restore_planner.dart';

enum SnapshotCompressionType {
  none(0),
  rle(1);

  const SnapshotCompressionType(this.wireValue);
  final int wireValue;
}

enum SnapshotPostCommand {
  loadNext(0x0100),
  copyLoader(0x0200),
  returnToBasic(0x0300),
  bankSwitch(0x0400);

  const SnapshotPostCommand(this.wireValue);
  final int wireValue;
}

class SnapshotRleMetadata {
  const SnapshotRleMetadata({
    required this.codeForMost,
    required this.codeForMultiples,
    required this.valueForMost,
  });

  final int codeForMost;
  final int codeForMultiples;
  final int valueForMost;
}

class SnapshotRleEncoding {
  SnapshotRleEncoding({
    required Uint8List payload,
    required this.metadata,
    required this.decompressionCounter,
  }) : payload = Uint8List.fromList(payload);

  final Uint8List payload;
  final SnapshotRleMetadata metadata;
  final int decompressionCounter;
}

class SnapshotRleCodec {
  const SnapshotRleCodec();

  SnapshotRleEncoding encode(Uint8List input, {int metadataAttempt = 0}) {
    if (metadataAttempt < 0 || metadataAttempt > 253) {
      throw ArgumentError.value(metadataAttempt, 'metadataAttempt');
    }
    final metadata = _metadata(input, metadataAttempt);
    final output = BytesBuilder(copy: false);
    var decompressionCounter = 0;

    void literal(int value) {
      if (_isEscape(metadata, value)) {
        output.add([value, value]);
      } else {
        output.addByte(value);
      }
      decompressionCounter++;
    }

    var offset = 0;
    while (offset < input.length) {
      final value = input[offset];
      var runLength = 1;
      while (offset + runLength < input.length &&
          input[offset + runLength] == value &&
          runLength < 255) {
        runLength++;
      }

      if (_isEscape(metadata, value)) {
        for (var count = 0; count < runLength; count++) {
          literal(value);
        }
      } else if (value == metadata.valueForMost) {
        var remaining = runLength;
        while (remaining > 0 &&
            (remaining <= 2 || _isEscape(metadata, remaining))) {
          literal(value);
          remaining--;
        }
        if (remaining > 0) {
          output.add([metadata.codeForMost, remaining]);
          decompressionCounter++;
        }
      } else {
        var remaining = runLength;
        while (remaining > 0 &&
            (remaining <= 3 || _isEscape(metadata, remaining))) {
          literal(value);
          remaining--;
        }
        if (remaining > 0) {
          output.add([metadata.codeForMultiples, value, remaining]);
          decompressionCounter++;
        }
      }
      offset += runLength;
    }

    if (decompressionCounter > 0xffff) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidTurboBlock,
        'RLE decompression counter exceeds receiver capacity',
      );
    }
    return SnapshotRleEncoding(
      payload: output.takeBytes(),
      metadata: metadata,
      decompressionCounter: decompressionCounter,
    );
  }

  SnapshotRleEncoding? encodeInline(Uint8List input, {int attempts = 5}) {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final encoded = encode(input, metadataAttempt: attempt);
      if (encoded.payload.length >= input.length) continue;
      if (canDecodeInline(input, encoded)) return encoded;
    }
    return null;
  }

  Uint8List decode(Uint8List input, SnapshotRleMetadata metadata) {
    final output = BytesBuilder(copy: false);
    var offset = 0;
    while (offset < input.length) {
      final value = input[offset++];
      if (value == metadata.codeForMost) {
        if (offset >= input.length) {
          throw const SnapshotException(
            SnapshotErrorCode.invalidTurboBlock,
            'Truncated code-for-most sequence',
          );
        }
        final count = input[offset++];
        if (count == metadata.codeForMost) {
          output.addByte(value);
        } else {
          if (count == 0) {
            throw const SnapshotException(
              SnapshotErrorCode.invalidTurboBlock,
              'Zero-length code-for-most sequence',
            );
          }
          output.add(
            Uint8List(count)..fillRange(0, count, metadata.valueForMost),
          );
        }
      } else if (value == metadata.codeForMultiples) {
        if (offset >= input.length) {
          throw const SnapshotException(
            SnapshotErrorCode.invalidTurboBlock,
            'Truncated code-for-multiples sequence',
          );
        }
        final repeated = input[offset++];
        if (repeated == metadata.codeForMultiples) {
          output.addByte(value);
        } else {
          if (offset >= input.length) {
            throw const SnapshotException(
              SnapshotErrorCode.invalidTurboBlock,
              'Missing multiple-run length',
            );
          }
          final count = input[offset++];
          if (count == 0) {
            throw const SnapshotException(
              SnapshotErrorCode.invalidTurboBlock,
              'Zero-length multiple-run sequence',
            );
          }
          output.add(Uint8List(count)..fillRange(0, count, repeated));
        }
      } else {
        output.addByte(value);
      }
    }
    return output.takeBytes();
  }

  bool canDecodeInline(Uint8List original, SnapshotRleEncoding encoding) {
    final compressed = encoding.payload;
    if (compressed.length >= original.length) return false;
    final memory = Uint8List(original.length);
    final sourceStart = original.length - compressed.length;
    memory.setRange(sourceStart, original.length, compressed);
    var read = sourceStart;
    var write = 0;
    var operations = 0;

    bool emit(int value, [int count = 1]) {
      if (count <= 0 || write + count > memory.length) return false;
      memory.fillRange(write, write + count, value);
      write += count;
      return true;
    }

    while (read < memory.length) {
      if (++operations > original.length + compressed.length) return false;
      final value = memory[read++];
      if (value == encoding.metadata.codeForMost) {
        if (read >= memory.length) return false;
        final count = memory[read++];
        if (count == encoding.metadata.codeForMost) {
          if (!emit(value)) return false;
        } else if (!emit(encoding.metadata.valueForMost, count)) {
          return false;
        }
      } else if (value == encoding.metadata.codeForMultiples) {
        if (read >= memory.length) return false;
        final repeated = memory[read++];
        if (repeated == encoding.metadata.codeForMultiples) {
          if (!emit(value)) return false;
        } else {
          if (read >= memory.length) return false;
          final count = memory[read++];
          if (!emit(repeated, count)) return false;
        }
      } else if (!emit(value)) {
        return false;
      }
    }
    if (write != original.length) return false;
    if (operations != encoding.decompressionCounter) return false;
    for (var index = 0; index < original.length; index++) {
      if (memory[index] != original[index]) return false;
    }
    return true;
  }

  SnapshotRleMetadata _metadata(Uint8List input, int attempt) {
    final frequency = List<int>.filled(256, 0);
    for (final value in input) {
      frequency[value]++;
    }
    final byFrequency = List<int>.generate(256, (value) => value)
      ..sort((left, right) {
        final comparison = frequency[left].compareTo(frequency[right]);
        return comparison != 0 ? comparison : right.compareTo(left);
      });
    final codeForMost = byFrequency[attempt];
    final codeForMultiples = byFrequency[attempt + 1];

    // Count every byte that participates in a sequential run of at least 3.
    // Unlike the C++ host implementation, the final run is deliberately flushed.
    final runFrequency = List<int>.filled(256, 0);
    var offset = 0;
    while (offset < input.length) {
      final value = input[offset];
      var runLength = 1;
      while (offset + runLength < input.length &&
          input[offset + runLength] == value) {
        runLength++;
      }
      if (runLength >= 3) runFrequency[value] += runLength;
      offset += runLength;
    }
    final byRunFrequency = List<int>.generate(256, (value) => value)
      ..sort((left, right) {
        final comparison = runFrequency[left].compareTo(runFrequency[right]);
        return comparison != 0 ? comparison : right.compareTo(left);
      });
    final valueForMost = byRunFrequency.lastWhere(
      (value) => value != codeForMost && value != codeForMultiples,
    );
    return SnapshotRleMetadata(
      codeForMost: codeForMost,
      codeForMultiples: codeForMultiples,
      valueForMost: valueForMost,
    );
  }

  bool _isEscape(SnapshotRleMetadata metadata, int value) =>
      value == metadata.codeForMost || value == metadata.codeForMultiples;
}

class SnapshotTurboHeader {
  const SnapshotTurboHeader({
    required this.length,
    required this.loadAddress,
    required this.destinationAddress,
    required this.compression,
    required this.payloadChecksum,
    required this.action,
    required this.clearOrBank,
    required this.codeForMost,
    required this.decompressionCounter,
    required this.codeForMultiples,
    required this.valueForMost,
  });

  static const int payloadByteLength = 17;
  static const int checksumOffset = payloadByteLength;
  static const int byteLength = payloadByteLength + 1;

  final int length;
  final int loadAddress;
  final int destinationAddress;
  final SnapshotCompressionType compression;
  final int payloadChecksum;
  final int action;
  final int clearOrBank;
  final int codeForMost;
  final int decompressionCounter;
  final int codeForMultiples;
  final int valueForMost;

  Uint8List toBytes() {
    final bytes = Uint8List(byteLength);
    void word(int offset, int value) {
      bytes[offset] = value & 0xff;
      bytes[offset + 1] = (value >> 8) & 0xff;
    }

    word(0, length);
    word(2, loadAddress);
    word(4, destinationAddress);
    bytes[6] = compression.wireValue;
    bytes[7] = payloadChecksum & 0xff;
    word(8, action);
    word(10, clearOrBank);
    bytes[12] = codeForMost & 0xff;
    word(13, decompressionCounter);
    bytes[15] = codeForMultiples & 0xff;
    bytes[16] = valueForMost & 0xff;
    bytes[checksumOffset] = snapshotChecksumCheckByte(
      bytes.take(checksumOffset),
    );
    return bytes;
  }

  SnapshotTurboHeader copyWith({
    int? length,
    int? loadAddress,
    int? destinationAddress,
    SnapshotCompressionType? compression,
    int? payloadChecksum,
    int? action,
    int? clearOrBank,
    int? codeForMost,
    int? decompressionCounter,
    int? codeForMultiples,
    int? valueForMost,
  }) => SnapshotTurboHeader(
    length: length ?? this.length,
    loadAddress: loadAddress ?? this.loadAddress,
    destinationAddress: destinationAddress ?? this.destinationAddress,
    compression: compression ?? this.compression,
    payloadChecksum: payloadChecksum ?? this.payloadChecksum,
    action: action ?? this.action,
    clearOrBank: clearOrBank ?? this.clearOrBank,
    codeForMost: codeForMost ?? this.codeForMost,
    decompressionCounter: decompressionCounter ?? this.decompressionCounter,
    codeForMultiples: codeForMultiples ?? this.codeForMultiples,
    valueForMost: valueForMost ?? this.valueForMost,
  );
}

class SnapshotTurboBlock {
  SnapshotTurboBlock({
    required this.name,
    required this.header,
    required Uint8List payload,
    required this.originalLength,
    required this.pauseBeforeMilliseconds,
    this.targetBank,
  }) : payload = Uint8List.fromList(payload);

  final String name;
  final SnapshotTurboHeader header;
  final Uint8List payload;
  final int originalLength;
  final int pauseBeforeMilliseconds;
  final int? targetBank;

  Uint8List get headerBytes => header.toBytes();

  SnapshotTurboBlock copyWith({
    SnapshotTurboHeader? header,
    int? pauseBeforeMilliseconds,
  }) => SnapshotTurboBlock(
    name: name,
    header: header ?? this.header,
    payload: payload,
    originalLength: originalLength,
    pauseBeforeMilliseconds:
        pauseBeforeMilliseconds ?? this.pauseBeforeMilliseconds,
    targetBank: targetBank,
  );
}

class SnapshotTurboStreamEncoder {
  const SnapshotTurboStreamEncoder({this.rle = const SnapshotRleCodec()});

  static const int decompressionSpeedKibPerSecond = 47;
  static const int copySpeedKibPerSecond = 162;

  final SnapshotRleCodec rle;

  List<SnapshotTurboBlock> encode(SnapshotRestorePlan plan) {
    plan.validate();
    if (plan.blocks.isEmpty) return const [];
    final blocks = <SnapshotTurboBlock>[];
    for (var index = 0; index < plan.blocks.length; index++) {
      final source = plan.blocks[index];
      final isFinal = index == plan.blocks.length - 1;
      blocks.add(
        _encodeBlock(
          source,
          explicitLoadAddress: isFinal ? plan.stagingAddress : 0,
          allowCompression: !isFinal,
        ),
      );
    }

    var previousBank = -1;
    for (var index = 0; index < plan.blocks.length; index++) {
      final bank = plan.blocks[index].bank;
      if (bank != null && bank != previousBank) {
        if (index == 0) {
          throw const SnapshotException(
            SnapshotErrorCode.invalidRestorePlan,
            'A banked block cannot be first',
          );
        }
        blocks[index - 1] = _withCommand(
          blocks[index - 1],
          SnapshotPostCommand.bankSwitch.wireValue,
          bank,
        );
        previousBank = bank;
      }
    }

    if (plan.finalOut7ffd >= 0 && plan.finalOut7ffd != previousBank) {
      if (blocks.length < 2) {
        throw const SnapshotException(
          SnapshotErrorCode.invalidRestorePlan,
          'No preceding block can restore 0x7ffd',
        );
      }
      blocks[blocks.length - 2] = _withCommand(
        blocks[blocks.length - 2],
        SnapshotPostCommand.bankSwitch.wireValue,
        plan.finalOut7ffd,
      );
    }

    blocks[0] = _withCommand(
      blocks[0],
      SnapshotPostCommand.copyLoader.wireValue,
      0,
    );
    final finalBlock = blocks.last;
    blocks[blocks.length - 1] = finalBlock.copyWith(
      header: finalBlock.header.copyWith(
        action: plan.registerCodeStart,
        clearOrBank: 0,
      ),
    );

    var pause = 100;
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      blocks[index] = block.copyWith(pauseBeforeMilliseconds: pause);
      pause = estimateProcessingMilliseconds(block);
    }
    return List.unmodifiable(blocks);
  }

  SnapshotTurboBlock _encodeBlock(
    SnapshotMemoryRange source, {
    required int explicitLoadAddress,
    required bool allowCompression,
  }) {
    if (source.data.length > 0xffff) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidTurboBlock,
        'Turbo payload exceeds the receiver length field',
      );
    }
    var payload = Uint8List.fromList(source.data);
    var compression = SnapshotCompressionType.none;
    var loadAddress = explicitLoadAddress;
    var destinationAddress = source.start;
    var codeForMost = 0;
    var codeForMultiples = 0;
    var valueForMost = 0;
    var decompressionCounter = 0;

    if (allowCompression &&
        source.data.length >= 200 &&
        destinationAddress != 0) {
      SnapshotRleEncoding? encoded;
      if (explicitLoadAddress == 0) {
        encoded = rle.encodeInline(source.data);
      } else {
        final candidate = rle.encode(source.data);
        if (candidate.payload.length < source.data.length) encoded = candidate;
      }
      if (encoded != null) {
        payload = encoded.payload;
        compression = SnapshotCompressionType.rle;
        codeForMost = encoded.metadata.codeForMost;
        codeForMultiples = encoded.metadata.codeForMultiples;
        valueForMost = encoded.metadata.valueForMost;
        decompressionCounter = adjustDecompressionCounter(
          encoded.decompressionCounter,
        );
        if (explicitLoadAddress == 0) {
          loadAddress =
              destinationAddress + source.data.length - payload.length;
        }
      }
    }

    if (explicitLoadAddress == 0 &&
        compression == SnapshotCompressionType.none) {
      loadAddress = destinationAddress;
      destinationAddress = 0;
    }
    final header = SnapshotTurboHeader(
      length: payload.length,
      loadAddress: loadAddress,
      destinationAddress: destinationAddress,
      compression: compression,
      payloadChecksum: snapshotPayloadChecksum(payload),
      action: SnapshotPostCommand.loadNext.wireValue,
      clearOrBank: 0,
      codeForMost: codeForMost,
      decompressionCounter: decompressionCounter,
      codeForMultiples: codeForMultiples,
      valueForMost: valueForMost,
    );
    return SnapshotTurboBlock(
      name: source.name,
      header: header,
      payload: payload,
      originalLength: source.data.length,
      pauseBeforeMilliseconds: 0,
      targetBank: source.bank,
    );
  }

  SnapshotTurboBlock _withCommand(
    SnapshotTurboBlock block,
    int action,
    int clearOrBank,
  ) {
    if (block.header.action != SnapshotPostCommand.loadNext.wireValue) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidTurboBlock,
        'A turbo block already has a post-block command',
      );
    }
    return block.copyWith(
      header: block.header.copyWith(action: action, clearOrBank: clearOrBank),
    );
  }

  int estimateProcessingMilliseconds(SnapshotTurboBlock block) {
    if (block.header.destinationAddress == 0) return 10;
    final speed = block.header.compression == SnapshotCompressionType.rle
        ? decompressionSpeedKibPerSecond
        : copySpeedKibPerSecond;
    return 10 + (block.originalLength * 1000) ~/ (1024 * speed);
  }
}

int adjustDecompressionCounter(int counter) {
  if (counter < 0 || counter > 0xffff) {
    throw ArgumentError.value(counter, 'counter');
  }
  final low = counter & 0xff;
  final decremented = (counter - 1) & 0xffff;
  final high = (((decremented >> 8) + 1) & 0xff) << 8;
  return high | low;
}

int snapshotPayloadChecksum(Iterable<int> bytes) {
  var checksum = 1;
  for (final byte in bytes) {
    checksum = (checksum + (byte & 0xff)) & 0xff;
    checksum = ((checksum << 1) | (checksum >> 7)) & 0xff;
  }
  return checksum;
}

/// Returns a final wire byte that makes [snapshotPayloadChecksum] equal zero.
int snapshotChecksumCheckByte(Iterable<int> bytes) =>
    (-snapshotPayloadChecksum(bytes)) & 0xff;

bool snapshotHeaderChecksumIsValid(Iterable<int> bytes) =>
    snapshotPayloadChecksum(bytes) == 0;
