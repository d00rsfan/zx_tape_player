import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/utils/definitions.dart';

enum TapeMediaKind { tape, snapshot }

class TapeImageData {
  const TapeImageData(this.bytes, this.fileName);

  final Uint8List bytes;
  final String fileName;
}

/// One safely resolved direct or archived input, shared by validation,
/// conversion, caching, display, and export.
class ResolvedTapeImage extends TapeImageData {
  ResolvedTapeImage({
    required Uint8List bytes,
    required String fileName,
    required this.sourceIdentity,
    required this.sourceFileName,
    required this.extension,
    required this.mediaKind,
    this.archiveFileName,
    this.innerPath,
  }) : super(Uint8List.fromList(bytes), fileName);

  final String sourceIdentity;
  final String sourceFileName;
  final String extension;
  final TapeMediaKind mediaKind;
  final String? archiveFileName;
  final String? innerPath;

  bool get isArchive => archiveFileName != null;
}

/// Avoids Android treating a ZX81 `.p` image as Pascal source. The pinned
/// file_picker version derives the ACTION_CREATE_DOCUMENT MIME type from the
/// supplied filename, and its detector maps lowercase `.p` to
/// `text/x-pascal`. Uppercase `.P` is byte-for-byte the same ZX81 format and
/// is recognized case-insensitively by this app and emulators.
String filePickerCompatibleTapeName(String fileName, {required bool android}) {
  if (!android || extension(fileName) != '.p') return fileName;
  return '${withoutExtension(fileName)}.P';
}

/// Resolves the first supported image without writing archive paths to disk.
/// When [model] is supplied, formats are restricted to that machine.
ResolvedTapeImage resolveTapeImage((Uint8List, String) args, {ZxModel? model}) {
  final (bytes, sourceIdentity) = args;
  final sourceFileName = basename(sourceIdentity);
  final supported =
      model?.localTapeExtensions ?? Definitions.supportedTapeExtensions;

  if (extension(sourceFileName).toLowerCase() != '.zip') {
    final ext = _extension(sourceFileName);
    if (!supported.contains(ext)) {
      throw FormatException('Unsupported image extension .$ext');
    }
    return ResolvedTapeImage(
      bytes: bytes,
      fileName: sourceFileName,
      sourceIdentity: sourceIdentity,
      sourceFileName: sourceFileName,
      extension: ext,
      mediaKind: _mediaKind(ext),
    );
  }

  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive) {
    if (!file.isFile) continue;
    final innerPath = _safeArchivePath(file.name);
    if (innerPath == null) continue;
    final ext = _extension(innerPath);
    if (supported.contains(ext)) {
      final content = file.content;
      return ResolvedTapeImage(
        bytes: Uint8List.fromList(content),
        fileName: posix.basename(innerPath),
        sourceIdentity: sourceIdentity,
        sourceFileName: sourceFileName,
        extension: ext,
        mediaKind: _mediaKind(ext),
        archiveFileName: sourceFileName,
        innerPath: innerPath,
      );
    }
  }

  throw FormatException(
    'No image supported by ${model?.name ?? 'this app'} found in zip archive',
  );
}

String _extension(String fileName) =>
    extension(fileName).replaceAll('.', '').toLowerCase();

TapeMediaKind _mediaKind(String extension) =>
    extension == 'z80' || extension == 'sna'
    ? TapeMediaKind.snapshot
    : TapeMediaKind.tape;

String? _safeArchivePath(String value) {
  final slashes = value.replaceAll(r'\', '/');
  if (slashes.isEmpty || slashes.startsWith('/')) return null;
  if (RegExp(r'^[A-Za-z]:/').hasMatch(slashes)) return null;
  final segments = slashes.split('/');
  if (segments.any((segment) => segment == '..')) return null;
  final normalized = posix.normalize(slashes);
  if (normalized == '.' || normalized.startsWith('../')) return null;
  return normalized;
}

/// Writes an export into its own temporary directory. Keeping the original
/// basename while isolating each export prevents a direct file selected from
/// an app cache directory from being overwritten or reused as its own staging
/// file.
Future<String> stageTapeImageForExport(
  TapeImageData image,
  String temporaryDirectoryPath,
) async {
  final exportDirectory = await Directory(
    temporaryDirectoryPath,
  ).createTemp('zx_tape_player_export_');
  final exportPath = join(exportDirectory.path, image.fileName);
  await File(exportPath).writeAsBytes(image.bytes, flush: true);
  return exportPath;
}

/// Copies the already-generated WAV byte-for-byte into an isolated export
/// directory, deriving a meaningful name from the resolved direct or ZIP
/// member name.
Future<String> stageWavForExport({
  required String cachedWavPath,
  required String imageFileName,
  required String temporaryDirectoryPath,
}) async {
  final cachedWav = File(cachedWavPath);
  if (!await cachedWav.exists()) {
    throw FileSystemException('Cached WAV does not exist', cachedWavPath);
  }
  final exportDirectory = await Directory(
    temporaryDirectoryPath,
  ).createTemp('zx_tape_player_wav_export_');
  final safeImageName = basename(imageFileName);
  final wavName = '${basenameWithoutExtension(safeImageName)}.wav';
  final exportPath = join(exportDirectory.path, wavName);
  await cachedWav.copy(exportPath);
  return exportPath;
}
