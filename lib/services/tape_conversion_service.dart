import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ReadBuffer;
import 'package:path/path.dart' show basenameWithoutExtension, extension;
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_converter.dart';
import 'package:zx_tape_player/snapshots/snapshot_decoder.dart';
import 'package:zx_tape_player/snapshots/snapshot_error.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_renderer.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
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
    required this.image,
    required this.outputPath,
    required this.progressPort,
    required this.audioFilterIndex,
    this.snapshotAssets,
    this.snapshotTurboProfileId,
    this.snapshotTurboCatalogRevision,
    this.snapshotInvertPolarity,
    this.snapshotSampleRateHz,
  });

  final ResolvedTapeImage image;
  final String outputPath;
  final SendPort progressPort;
  final int audioFilterIndex;
  final SnapshotAssetBundle? snapshotAssets;
  final String? snapshotTurboProfileId;
  final String? snapshotTurboCatalogRevision;
  final bool? snapshotInvertPolarity;
  final int? snapshotSampleRateHz;
}

class TapeConversionMessage {
  const TapeConversionMessage({
    required this.code,
    required this.message,
    this.offset,
  });

  final String code;
  final String message;
  final int? offset;
}

class SnapshotProtocolMetadata {
  const SnapshotProtocolMetadata({
    required this.protocolVersion,
    required this.receiverSha256,
    required this.registerSha256,
    required this.wavProfile,
    required this.turboProfileId,
    required this.turboCatalogRevision,
    required this.turboTimingFingerprint,
    required this.invertedPolarity,
    required this.sampleRateHz,
  });

  final String protocolVersion;
  final String receiverSha256;
  final String registerSha256;
  final String wavProfile;
  final String turboProfileId;
  final String turboCatalogRevision;
  final String turboTimingFingerprint;
  final bool invertedPolarity;
  final int sampleRateHz;
}

class TapeConversionResponse {
  const TapeConversionResponse({
    required this.mediaKind,
    required this.blocks,
    required this.warnings,
    this.error,
    this.protocolMetadata,
  });

  final TapeMediaKind mediaKind;
  final List<TapeBlockInfo> blocks;
  final List<TapeConversionMessage> warnings;
  final TapeConversionMessage? error;
  final SnapshotProtocolMetadata? protocolMetadata;

  bool get isSuccess => error == null;
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
Future<bool> isTapeImageSupported(
  Uint8List bytes,
  String fileName, {
  ZxModel? model,
}) async {
  try {
    final image = resolveTapeImage((bytes, fileName), model: model);
    return await isResolvedTapeImageSupported(image);
  } catch (_) {
    return false;
  }
}

Future<bool> isResolvedTapeImageSupported(ResolvedTapeImage image) async {
  try {
    if (image.mediaKind == TapeMediaKind.snapshot) {
      const SnapshotDecoder().decode(image.bytes, image.fileName);
      return true;
    }
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
  final image = request.image;
  if (image.mediaKind == TapeMediaKind.snapshot) {
    return _convertSnapshotImage(request);
  }
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
  return TapeConversionResponse(
    mediaKind: TapeMediaKind.tape,
    blocks: blocks,
    warnings: [
      for (final warning in warnings)
        TapeConversionMessage(code: 'tape_warning', message: warning),
    ],
  );
}

Future<TapeConversionResponse> _convertSnapshotImage(
  TapeConversionRequest request,
) async {
  try {
    final assets = request.snapshotAssets;
    if (assets == null) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidAsset,
        'Snapshot receiver assets were not supplied to the worker',
      );
    }
    final profileId = request.snapshotTurboProfileId;
    final catalogRevision = request.snapshotTurboCatalogRevision;
    final invertPolarity = request.snapshotInvertPolarity;
    final sampleRateHz = request.snapshotSampleRateHz;
    if (profileId == null ||
        catalogRevision == null ||
        invertPolarity == null ||
        sampleRateHz == null) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidTurboBlock,
        'Snapshot signal settings were not supplied to the worker',
      );
    }
    final turboProfile = SnapshotTurboProfiles.resolve(
      id: profileId,
      catalogRevision: catalogRevision,
    );
    final sampleRate = SnapshotAudioSampleRate.tryFromHz(sampleRateHz);
    if (sampleRate == null) {
      throw SnapshotException(
        SnapshotErrorCode.invalidTurboBlock,
        'Unsupported snapshot sample rate $sampleRateHz Hz',
      );
    }
    final result = const SnapshotConverter().convert(
      snapshotBytes: request.image.bytes,
      fileName: request.image.fileName,
      assets: assets,
      turboProfile: turboProfile,
      invertPolarity: invertPolarity,
      sampleRate: sampleRate,
      onProgress: request.progressPort.send,
    );
    final blocks = <TapeBlockInfo>[];
    for (var index = 0; index < result.wav.blocks.length; index++) {
      final rendered = result.wav.blocks[index];
      final turboIndex = index - 2;
      blocks.add(
        TapeBlockInfo(
          index: index,
          typeName: 'Snapshot',
          title: rendered.name,
          dataLength: turboIndex >= 0
              ? result.turboBlocks[turboIndex].originalLength
              : null,
          isHeader: index < 2,
          sampleOffset: rendered.startFrame,
          timeOffset: rendered.start,
          duration: rendered.duration,
        ),
      );
    }
    await File(
      request.outputPath,
    ).writeAsBytes(result.wav.wavBytes, flush: true);
    final layout = SnapshotReceiverManifest.layoutFor(result.snapshot.machine);
    return TapeConversionResponse(
      mediaKind: TapeMediaKind.snapshot,
      blocks: blocks,
      warnings: [
        for (final warning in result.warnings)
          TapeConversionMessage(
            code: warning.code.name,
            message: warning.message,
          ),
      ],
      protocolMetadata: SnapshotProtocolMetadata(
        protocolVersion: SnapshotReceiverManifest.protocolVersion,
        receiverSha256: layout.sha256,
        registerSha256: SnapshotReceiverManifest.registerSha256,
        wavProfile: SnapshotWavRenderer.profileIdFor(sampleRate),
        turboProfileId: result.turboProfile.id,
        turboCatalogRevision: SnapshotTurboProfiles.catalogRevision,
        turboTimingFingerprint: result.turboProfile.timingFingerprint,
        invertedPolarity: result.invertPolarity,
        sampleRateHz: result.sampleRate.hz,
      ),
    );
  } on SnapshotException catch (error) {
    return TapeConversionResponse(
      mediaKind: TapeMediaKind.snapshot,
      blocks: const [],
      warnings: const [],
      error: TapeConversionMessage(
        code: error.code.name,
        message: error.message,
        offset: error.offset,
      ),
    );
  }
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
