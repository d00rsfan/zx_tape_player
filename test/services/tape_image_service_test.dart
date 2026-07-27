import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show basename, join;
import 'package:zx_tape_player/services/tape_image_service.dart';

void main() {
  test(
    'direct P export is byte-identical and uses a separate staging path',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'zx_p_export_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final bytes = _buildPFile(160);
      final source = File(join(tempDirectory.path, 'mazogs.p'));
      await source.writeAsBytes(bytes);

      final image = resolveTapeImage((await source.readAsBytes(), source.path));
      final stagedPath = await stageTapeImageForExport(
        image,
        tempDirectory.path,
      );

      expect(stagedPath, isNot(source.path));
      expect(basename(stagedPath), 'mazogs.p');
      expect(await File(stagedPath).readAsBytes(), orderedEquals(bytes));
      expect(await source.readAsBytes(), orderedEquals(bytes));
    },
  );

  test('ZIP export resolves the inner tape name and bytes', () {
    final tapeBytes = Uint8List.fromList([2, 0, 0, 0]);
    final archive = Archive()
      ..addFile(ArchiveFile('nested/game.tap', tapeBytes.length, tapeBytes));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

    final image = resolveTapeImage((zipBytes, 'download.tap.zip'));

    expect(image.fileName, 'game.tap');
    expect(image.bytes, orderedEquals(tapeBytes));
  });

  for (final extension in <String>['81', 'p81', 'o', '80']) {
    test('ZIP extraction accepts .$extension tape images', () {
      final tapeBytes = Uint8List.fromList([1, 2, 3, 4]);
      final archive = Archive()
        ..addFile(
          ArchiveFile('nested/game.$extension', tapeBytes.length, tapeBytes),
        );
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final image = resolveTapeImage((zipBytes, 'download.zip'));

      expect(image.fileName, 'game.$extension');
      expect(image.bytes, orderedEquals(tapeBytes));
    });
  }

  test('Android file picker does not classify P images as Pascal source', () {
    expect(filePickerCompatibleTapeName('mazogs.p', android: true), 'mazogs.P');
    expect(
      filePickerCompatibleTapeName('mazogs.p', android: false),
      'mazogs.p',
    );
    expect(filePickerCompatibleTapeName('game.tap', android: true), 'game.tap');
  });
}

Uint8List _buildPFile(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (i * 37 + 1) & 0xff;
  }
  final eLine = 0x4009 + length;
  bytes[11] = eLine & 0xff;
  bytes[12] = eLine >> 8;
  return bytes;
}
