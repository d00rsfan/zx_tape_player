import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' show join;
import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_renderer.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class SnapshotCacheIdentity {
  const SnapshotCacheIdentity({
    required this.sourceSha256,
    required this.sourceFileName,
    required this.selectedInnerName,
    required this.protocolVersion,
    required this.receiver48Sha256,
    required this.receiver128Sha256,
    required this.registerSha256,
    required this.wavProfile,
    required this.turboProfileId,
    required this.turboCatalogRevision,
    required this.turboTimingFingerprint,
    required this.invertedPolarity,
    required this.sampleRateHz,
  });

  factory SnapshotCacheIdentity.create(
    ResolvedTapeImage image,
    SnapshotAssetBundle assets, {
    required SnapshotTurboProfile turboProfile,
    required bool invertPolarity,
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
    String protocolVersion = SnapshotReceiverManifest.protocolVersion,
    String? wavProfile,
  }) {
    assets.verify();
    return SnapshotCacheIdentity(
      sourceSha256: sha256.convert(image.bytes).toString(),
      sourceFileName: image.sourceFileName,
      selectedInnerName: image.innerPath ?? image.fileName,
      protocolVersion: protocolVersion,
      receiver48Sha256: sha256.convert(assets.receiver48Tap).toString(),
      receiver128Sha256: sha256.convert(assets.receiver128Tap).toString(),
      registerSha256: sha256.convert(assets.registerBlob).toString(),
      wavProfile: wavProfile ?? SnapshotWavRenderer.profileIdFor(sampleRate),
      turboProfileId: turboProfile.id,
      turboCatalogRevision: SnapshotTurboProfiles.catalogRevision,
      turboTimingFingerprint: turboProfile.timingFingerprint,
      invertedPolarity: invertPolarity,
      sampleRateHz: sampleRate.hz,
    );
  }

  static const String defaultWavProfile = SnapshotWavRenderer.profileId;

  final String sourceSha256;
  final String sourceFileName;
  final String selectedInnerName;
  final String protocolVersion;
  final String receiver48Sha256;
  final String receiver128Sha256;
  final String registerSha256;
  final String wavProfile;
  final String turboProfileId;
  final String turboCatalogRevision;
  final String turboTimingFingerprint;
  final bool invertedPolarity;
  final int sampleRateHz;

  Map<String, Object> toJson() => {
    'sourceSha256': sourceSha256,
    'sourceFileName': sourceFileName,
    'selectedInnerName': selectedInnerName,
    'protocolVersion': protocolVersion,
    'receiver48Sha256': receiver48Sha256,
    'receiver128Sha256': receiver128Sha256,
    'registerSha256': registerSha256,
    'wavProfile': wavProfile,
    'turboProfileId': turboProfileId,
    'turboCatalogRevision': turboCatalogRevision,
    'turboTimingFingerprint': turboTimingFingerprint,
    'invertedPolarity': invertedPolarity,
    'sampleRateHz': sampleRateHz,
  };

  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  SnapshotCacheIdentity copyWith({
    String? sourceSha256,
    String? sourceFileName,
    String? selectedInnerName,
    String? protocolVersion,
    String? receiver48Sha256,
    String? receiver128Sha256,
    String? registerSha256,
    String? wavProfile,
    String? turboProfileId,
    String? turboCatalogRevision,
    String? turboTimingFingerprint,
    bool? invertedPolarity,
    int? sampleRateHz,
  }) => SnapshotCacheIdentity(
    sourceSha256: sourceSha256 ?? this.sourceSha256,
    sourceFileName: sourceFileName ?? this.sourceFileName,
    selectedInnerName: selectedInnerName ?? this.selectedInnerName,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    receiver48Sha256: receiver48Sha256 ?? this.receiver48Sha256,
    receiver128Sha256: receiver128Sha256 ?? this.receiver128Sha256,
    registerSha256: registerSha256 ?? this.registerSha256,
    wavProfile: wavProfile ?? this.wavProfile,
    turboProfileId: turboProfileId ?? this.turboProfileId,
    turboCatalogRevision: turboCatalogRevision ?? this.turboCatalogRevision,
    turboTimingFingerprint:
        turboTimingFingerprint ?? this.turboTimingFingerprint,
    invertedPolarity: invertedPolarity ?? this.invertedPolarity,
    sampleRateHz: sampleRateHz ?? this.sampleRateHz,
  );
}

class SnapshotCachePaths {
  const SnapshotCachePaths({required this.wavPath, required this.sidecarPath});

  final String wavPath;
  final String sidecarPath;
}

class SnapshotCacheEntry {
  const SnapshotCacheEntry({
    required this.response,
    required this.wavPath,
    required this.fromCache,
  });

  final TapeConversionResponse response;
  final String wavPath;
  final bool fromCache;
}

class SnapshotCacheStore {
  const SnapshotCacheStore();

  static const int sidecarVersion = 5;

  SnapshotCachePaths paths(String directory, SnapshotCacheIdentity identity) {
    final wavPath = join(directory, 'snapshot_${identity.digest}.wav');
    return SnapshotCachePaths(wavPath: wavPath, sidecarPath: '$wavPath.json');
  }

  Future<SnapshotCacheEntry?> read(
    SnapshotCachePaths paths,
    SnapshotCacheIdentity identity,
  ) async {
    try {
      final wavFile = File(paths.wavPath);
      final sidecarFile = File(paths.sidecarPath);
      if (!await wavFile.exists() || !await sidecarFile.exists()) return null;
      final dynamic decoded = jsonDecode(await sidecarFile.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != sidecarVersion ||
          decoded['mediaKind'] != TapeMediaKind.snapshot.name ||
          jsonEncode(decoded['identity']) != jsonEncode(identity.toJson())) {
        return null;
      }

      final wav = await wavFile.readAsBytes();
      if (!_validSnapshotWav(wav, identity.sampleRateHz) ||
          decoded['wavLength'] != wav.length ||
          decoded['wavSha256'] != sha256.convert(wav).toString()) {
        return null;
      }
      final rawBlocks = decoded['blocks'];
      final rawWarnings = decoded['warnings'];
      final rawProtocol = decoded['protocol'];
      if (rawBlocks is! List ||
          rawWarnings is! List ||
          rawProtocol is! Map<String, dynamic>) {
        return null;
      }
      final receiverSha256 = rawProtocol['receiverSha256'];
      if (rawProtocol['protocolVersion'] != identity.protocolVersion ||
          rawProtocol['registerSha256'] != identity.registerSha256 ||
          rawProtocol['wavProfile'] != identity.wavProfile ||
          rawProtocol['turboProfileId'] != identity.turboProfileId ||
          rawProtocol['turboCatalogRevision'] !=
              identity.turboCatalogRevision ||
          rawProtocol['turboTimingFingerprint'] !=
              identity.turboTimingFingerprint ||
          rawProtocol['invertedPolarity'] != identity.invertedPolarity ||
          rawProtocol['sampleRateHz'] != identity.sampleRateHz ||
          (receiverSha256 != identity.receiver48Sha256 &&
              receiverSha256 != identity.receiver128Sha256)) {
        return null;
      }
      final blocks = rawBlocks.map(_blockFromJson).toList(growable: false);
      final warnings = rawWarnings
          .map((value) => _messageFromJson(value as Map<String, dynamic>))
          .toList(growable: false);
      final response = TapeConversionResponse(
        mediaKind: TapeMediaKind.snapshot,
        blocks: blocks,
        warnings: warnings,
        protocolMetadata: SnapshotProtocolMetadata(
          protocolVersion: rawProtocol['protocolVersion'] as String,
          receiverSha256: receiverSha256 as String,
          registerSha256: rawProtocol['registerSha256'] as String,
          wavProfile: rawProtocol['wavProfile'] as String,
          turboProfileId: rawProtocol['turboProfileId'] as String,
          turboCatalogRevision: rawProtocol['turboCatalogRevision'] as String,
          turboTimingFingerprint:
              rawProtocol['turboTimingFingerprint'] as String,
          invertedPolarity: rawProtocol['invertedPolarity'] as bool,
          sampleRateHz: rawProtocol['sampleRateHz'] as int,
        ),
      );
      return SnapshotCacheEntry(
        response: response,
        wavPath: paths.wavPath,
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reuses a validated WAV/sidecar pair or creates it exactly once through
  /// [convert]. Keeping this decision at the cache seam makes player
  /// recreation indistinguishable from an in-memory cache hit.
  Future<SnapshotCacheEntry> getOrCreate(
    SnapshotCachePaths paths,
    SnapshotCacheIdentity identity,
    Future<TapeConversionResponse> Function(String wavPath) convert,
  ) async {
    final cached = await read(paths, identity);
    if (cached != null) return cached;

    final response = await convert(paths.wavPath);
    if (response.isSuccess) {
      await write(paths, identity, response);
    }
    return SnapshotCacheEntry(
      response: response,
      wavPath: paths.wavPath,
      fromCache: false,
    );
  }

  Future<void> write(
    SnapshotCachePaths paths,
    SnapshotCacheIdentity identity,
    TapeConversionResponse response,
  ) async {
    if (!response.isSuccess ||
        response.mediaKind != TapeMediaKind.snapshot ||
        response.protocolMetadata == null) {
      throw ArgumentError('Only a successful snapshot response can be cached');
    }
    final wavFile = File(paths.wavPath);
    if (!await wavFile.exists()) {
      throw const FileSystemException('Snapshot WAV does not exist');
    }
    final wav = await wavFile.readAsBytes();
    if (!_validSnapshotWav(wav, identity.sampleRateHz)) {
      throw const FormatException('Snapshot WAV profile is invalid');
    }
    final protocol = response.protocolMetadata!;
    if (protocol.protocolVersion != identity.protocolVersion ||
        protocol.registerSha256 != identity.registerSha256 ||
        protocol.wavProfile != identity.wavProfile ||
        protocol.turboProfileId != identity.turboProfileId ||
        protocol.turboCatalogRevision != identity.turboCatalogRevision ||
        protocol.turboTimingFingerprint != identity.turboTimingFingerprint ||
        protocol.invertedPolarity != identity.invertedPolarity ||
        protocol.sampleRateHz != identity.sampleRateHz ||
        (protocol.receiverSha256 != identity.receiver48Sha256 &&
            protocol.receiverSha256 != identity.receiver128Sha256)) {
      throw const FormatException(
        'Snapshot response protocol does not match its cache identity',
      );
    }
    final sidecar = <String, Object>{
      'version': sidecarVersion,
      'mediaKind': TapeMediaKind.snapshot.name,
      'identity': identity.toJson(),
      'wavLength': wav.length,
      'wavSha256': sha256.convert(wav).toString(),
      'blocks': response.blocks.map(_blockToJson).toList(growable: false),
      'warnings': response.warnings.map(_messageToJson).toList(growable: false),
      'protocol': {
        'protocolVersion': protocol.protocolVersion,
        'receiverSha256': protocol.receiverSha256,
        'registerSha256': protocol.registerSha256,
        'wavProfile': protocol.wavProfile,
        'turboProfileId': protocol.turboProfileId,
        'turboCatalogRevision': protocol.turboCatalogRevision,
        'turboTimingFingerprint': protocol.turboTimingFingerprint,
        'invertedPolarity': protocol.invertedPolarity,
        'sampleRateHz': protocol.sampleRateHz,
      },
    };
    await File(
      paths.sidecarPath,
    ).writeAsString(jsonEncode(sidecar), flush: true);
  }

  static Map<String, Object?> _blockToJson(TapeBlockInfo block) => {
    'index': block.index,
    'typeName': block.typeName,
    'title': block.title,
    'dataLength': block.dataLength,
    'isHeader': block.isHeader,
    'sampleOffset': block.sampleOffset,
    'timeOffsetUs': block.timeOffset.inMicroseconds,
    'durationUs': block.duration.inMicroseconds,
  };

  static TapeBlockInfo _blockFromJson(dynamic value) {
    final map = value as Map<String, dynamic>;
    return TapeBlockInfo(
      index: map['index'] as int,
      typeName: map['typeName'] as String,
      title: map['title'] as String?,
      dataLength: map['dataLength'] as int?,
      isHeader: map['isHeader'] as bool,
      sampleOffset: map['sampleOffset'] as int,
      timeOffset: Duration(microseconds: map['timeOffsetUs'] as int),
      duration: Duration(microseconds: map['durationUs'] as int),
    );
  }

  static Map<String, Object?> _messageToJson(TapeConversionMessage message) => {
    'code': message.code,
    'message': message.message,
    'offset': message.offset,
  };

  static TapeConversionMessage _messageFromJson(Map<String, dynamic> map) =>
      TapeConversionMessage(
        code: map['code'] as String,
        message: map['message'] as String,
        offset: map['offset'] as int?,
      );

  static bool _validSnapshotWav(List<int> wav, int expectedSampleRateHz) {
    if (SnapshotAudioSampleRate.tryFromHz(expectedSampleRateHz) == null ||
        wav.length < 44 ||
        String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE' ||
        String.fromCharCodes(wav.sublist(36, 40)) != 'data') {
      return false;
    }
    final bytes = wav is Uint8List ? wav : Uint8List.fromList(wav);
    final data = ByteData.sublistView(bytes);
    final dataLength = data.getUint32(40, Endian.little);
    final paddingLength = dataLength.isOdd ? 1 : 0;
    return data.getUint32(4, Endian.little) == wav.length - 8 &&
        data.getUint16(20, Endian.little) == 1 &&
        data.getUint16(22, Endian.little) == SnapshotWavRenderer.channels &&
        data.getUint32(24, Endian.little) == expectedSampleRateHz &&
        data.getUint32(28, Endian.little) ==
            expectedSampleRateHz * SnapshotWavRenderer.channels &&
        data.getUint16(32, Endian.little) == SnapshotWavRenderer.channels &&
        data.getUint16(34, Endian.little) ==
            SnapshotWavRenderer.bitsPerSample &&
        44 + dataLength + paddingLength == wav.length &&
        (paddingLength == 0 || wav.last == 0);
  }
}
