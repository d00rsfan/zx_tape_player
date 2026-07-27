import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ReadBuffer;
import 'package:path/path.dart' show basenameWithoutExtension, extension;
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/utils/definitions.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';
// The converter package does not yet expose a public builder for raw
// ZX80/ZX81 streams. These two implementation imports let us reuse its exact
// pulse synthesis and all four audio filters without duplicating that logic.
// ignore: implementation_imports
import 'package:zx_tape_to_wav_x/src/lib/blocks.dart';
// ignore: implementation_imports
import 'package:zx_tape_to_wav_x/src/lib/wav_builder.dart';

/// Data sent to the conversion isolate. Every field is explicitly
/// isolate-safe; in particular, this deliberately excludes service objects,
/// files, and stream controllers.
class TapeConversionRequest {
  const TapeConversionRequest({
    required this.tapeBytes,
    required this.fileName,
    required this.outputPath,
    required this.progressPort,
    required this.audioFilterIndex,
  });

  final Uint8List tapeBytes;
  final String fileName;
  final String outputPath;
  final SendPort progressPort;
  final int audioFilterIndex;
}

class TapeConversionResponse {
  const TapeConversionResponse(this.blocks, this.warnings);

  final List<TapeBlockInfo> blocks;
  final List<String> warnings;
}

class _RawSinclairTape {
  const _RawSinclairTape({
    required this.data,
    required this.tapeName,
    this.displayTitle,
  });

  final Uint8List data;
  final Uint8List tapeName;
  final String? displayTitle;
}

const _zx81Origin = 0x4009;
const _zx81ELineOffset = 0x4014 - _zx81Origin;
const _zx81MinimumLength = 0x407d - _zx81Origin;
const _zx80Origin = 0x4000;
const _zx80ELineOffset = 0x400a - _zx80Origin;
const _zx80MinimumLength = 0x4029 - _zx80Origin;
const _maximumP81NameLength = 127;

/// Checks all formats accepted by the production conversion worker, including
/// ZIP-wrapped images. Unlike extension-only checks this rejects truncated
/// ZX80/ZX81 memory images whose E_LINE pointer cannot fit in the file.
Future<bool> isTapeImageSupported(Uint8List bytes, String fileName) async {
  try {
    final image = resolveTapeImage((bytes, fileName));
    if (_tryParseRawSinclairTape(image) != null) return true;
    final tape = await ZxTape.create(image.bytes, fileName: image.fileName);
    return tape.tapeType != TapeType.unknown;
  } catch (_) {
    return false;
  }
}

Future<TapeConversionResponse> convertTapeImage(
  TapeConversionRequest request,
) async {
  final image = resolveTapeImage((request.tapeBytes, request.fileName));
  final filter = AudioFilterType.values[request.audioFilterIndex];
  final rawTape = _tryParseRawSinclairTape(image);

  late Uint8List wavBytes;
  late List<TapeBlockInfo> blocks;
  late List<String> warnings;
  if (rawTape != null) {
    final result = _convertRawSinclairTape(
      rawTape,
      filter,
      request.progressPort,
    );
    wavBytes = result.wavBytes;
    blocks = result.blocks;
    warnings = result.warnings;
  } else {
    final tape = await ZxTape.create(image.bytes, fileName: image.fileName);
    final result = await tape.toWavBytesWithBlocks(
      audioFilterType: filter,
      frequency: Definitions.wavFrequency,
      progress: request.progressPort.send,
    );
    wavBytes = result.wavBytes;
    blocks = result.blocks;
    warnings = result.warnings;
  }

  await File(request.outputPath).writeAsBytes(wavBytes, flush: true);
  return TapeConversionResponse(blocks, warnings);
}

TapeConversionResult _convertRawSinclairTape(
  _RawSinclairTape tape,
  AudioFilterType filter,
  SendPort progressPort,
) {
  final dataBlock = Zx81DataBlock(
    0,
    ReadBuffer(ByteData.sublistView(tape.data)),
    name: tape.tapeName,
    dataLength: tape.data.length,
  );
  final pauseBlock = PauseOrStopTheTapeBlock(
    1,
    ReadBuffer(ByteData(0)),
    duration: 2000,
  );
  final builder = WavBuilder(
    <BlockBase>[dataBlock, pauseBlock],
    Definitions.wavFrequency,
    progressPort.send,
    audioFilterType: filter,
  );
  final wavBytes = builder.toBytes();
  final blocks = List<TapeBlockInfo>.of(builder.blockInfos);

  // ZX80 tape data has no embedded filename. Showing the host filename in the
  // block browser is useful, but it must not be emitted into the audio stream.
  if (tape.displayTitle != null && blocks.isNotEmpty) {
    final block = blocks.first;
    blocks[0] = TapeBlockInfo(
      index: block.index,
      typeName: block.typeName,
      title: tape.displayTitle,
      dataLength: block.dataLength,
      isHeader: block.isHeader,
      sampleOffset: block.sampleOffset,
      timeOffset: block.timeOffset,
      duration: block.duration,
    );
  }

  return TapeConversionResult(wavBytes, blocks, warnings: builder.warnings);
}

_RawSinclairTape? _tryParseRawSinclairTape(TapeImageData image) {
  final ext = extension(image.fileName).toLowerCase();
  if (ext == '.p81') return _tryParseP81(image.bytes);
  if (ext == '.o' || ext == '.80') {
    return _tryParseZx80(image.bytes, image.fileName);
  }
  return null;
}

_RawSinclairTape? _tryParseP81(Uint8List bytes) {
  var nameEnd = -1;
  final scanLength = bytes.length < _maximumP81NameLength
      ? bytes.length
      : _maximumP81NameLength;
  for (var i = 0; i < scanLength; i++) {
    if (bytes[i] & 0x80 != 0) {
      nameEnd = i;
      break;
    }
  }
  if (nameEnd < 0) return null;

  final data = Uint8List.fromList(bytes.sublist(nameEnd + 1));
  final dataLength = _memoryImageLength(
    data,
    origin: _zx81Origin,
    eLineOffset: _zx81ELineOffset,
    minimumLength: _zx81MinimumLength,
  );
  if (dataLength == null) return null;

  return _RawSinclairTape(
    data: Uint8List.fromList(data.sublist(0, dataLength)),
    tapeName: Uint8List.fromList(bytes.sublist(0, nameEnd + 1)),
  );
}

_RawSinclairTape? _tryParseZx80(Uint8List bytes, String fileName) {
  final dataLength = _memoryImageLength(
    bytes,
    origin: _zx80Origin,
    eLineOffset: _zx80ELineOffset,
    minimumLength: _zx80MinimumLength,
  );
  if (dataLength == null) return null;

  return _RawSinclairTape(
    data: Uint8List.fromList(bytes.sublist(0, dataLength)),
    tapeName: Uint8List(0),
    displayTitle: basenameWithoutExtension(fileName),
  );
}

int? _memoryImageLength(
  Uint8List bytes, {
  required int origin,
  required int eLineOffset,
  required int minimumLength,
}) {
  if (bytes.length < minimumLength || eLineOffset + 1 >= bytes.length) {
    return null;
  }
  final eLine = bytes[eLineOffset] | (bytes[eLineOffset + 1] << 8);
  final dataLength = eLine - origin;
  if (dataLength < minimumLength || dataLength > bytes.length) return null;
  return dataLength;
}
