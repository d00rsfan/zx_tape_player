import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:zx_tape_player/utils/definitions.dart';

class TapeImageData {
  const TapeImageData(this.bytes, this.fileName);

  final Uint8List bytes;
  final String fileName;
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

/// Returns the tape bytes and name represented by [args]. ZIP archives are
/// unpacked to the first supported tape image; direct tape files are returned
/// unchanged.
TapeImageData resolveTapeImage((Uint8List, String) args) {
  var (bytes, fileName) = args;
  fileName = basename(fileName);

  if (extension(fileName).toLowerCase() != '.zip') {
    return TapeImageData(bytes, fileName);
  }

  final archive = ZipDecoder().decodeBytes(bytes);
  for (final file in archive) {
    if (!file.isFile) continue;
    final ext = extension(file.name).replaceAll('.', '').toLowerCase();
    if (Definitions.supportedTapeExtensions.contains(ext)) {
      return TapeImageData(
        Uint8List.fromList(file.content as List<int>),
        basename(file.name),
      );
    }
  }

  throw const FormatException('No tape file found in zip archive');
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
