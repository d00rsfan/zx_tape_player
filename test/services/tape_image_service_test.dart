import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show basename, join;
import 'package:zx_tape_player/models/zx_model.dart';
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
    expect(image.sourceFileName, 'download.tap.zip');
    expect(image.innerPath, 'nested/game.tap');
    expect(image.mediaKind, TapeMediaKind.tape);
  });

  test('all existing tape extensions retain direct and ZIP resolution', () {
    const extensions = <String>['tap', 'tzx', 'p', '81', 'p81', 'o', '80'];
    for (final extension in extensions) {
      final bytes = Uint8List.fromList([extension.length, 2, 3, 4]);
      final sourcePath = '/downloads/game.$extension';
      final direct = resolveTapeImage((bytes, sourcePath));
      expect(direct.fileName, 'game.$extension', reason: extension);
      expect(direct.sourceIdentity, sourcePath, reason: extension);
      expect(direct.innerPath, isNull, reason: extension);
      expect(direct.bytes, orderedEquals(bytes), reason: extension);
      expect(direct.mediaKind, TapeMediaKind.tape, reason: extension);

      final archive = Archive()
        ..addFile(ArchiveFile('nested/game.$extension', bytes.length, bytes));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final zipped = resolveTapeImage((zipBytes, '/downloads/bundle.zip'));
      expect(zipped.fileName, 'game.$extension', reason: extension);
      expect(zipped.sourceIdentity, '/downloads/bundle.zip', reason: extension);
      expect(zipped.archiveFileName, 'bundle.zip', reason: extension);
      expect(zipped.innerPath, 'nested/game.$extension', reason: extension);
      expect(zipped.bytes, orderedEquals(bytes), reason: extension);
      expect(zipped.mediaKind, TapeMediaKind.tape, reason: extension);
    }
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

  for (final extension in <String>['z80', 'sna']) {
    test('Spectrum resolves direct and zipped .$extension snapshots', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final direct = resolveTapeImage((
        bytes,
        '/source/GAME.${extension.toUpperCase()}',
      ), model: ZxModel.zxSpectrum);
      expect(direct.extension, extension);
      expect(direct.mediaKind, TapeMediaKind.snapshot);
      expect(direct.isArchive, isFalse);

      final archive = Archive()
        ..addFile(ArchiveFile('safe/game.$extension', bytes.length, bytes));
      final zipped = resolveTapeImage((
        Uint8List.fromList(ZipEncoder().encode(archive)),
        'download.zip',
      ), model: ZxModel.zxSpectrum);
      expect(zipped.fileName, 'game.$extension');
      expect(zipped.innerPath, 'safe/game.$extension');
      expect(zipped.archiveFileName, 'download.zip');
    });
  }

  test('direct and ZIP snapshot exports preserve bytes and names', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'snapshot_source_export_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    for (final extension in <String>['z80', 'sna']) {
      final bytes = Uint8List.fromList([1, 4, extension.length, 9]);
      final direct = resolveTapeImage((bytes, 'state.$extension'));
      final directExport = await stageTapeImageForExport(
        direct,
        tempDirectory.path,
      );
      expect(basename(directExport), 'state.$extension');
      expect(await File(directExport).readAsBytes(), orderedEquals(bytes));

      final archive = Archive()
        ..addFile(ArchiveFile('nested/inner.$extension', bytes.length, bytes));
      final zipped = resolveTapeImage((
        Uint8List.fromList(ZipEncoder().encode(archive)),
        'bundle.zip',
      ));
      final innerExport = await stageTapeImageForExport(
        zipped,
        tempDirectory.path,
      );
      expect(basename(innerExport), 'inner.$extension');
      expect(await File(innerExport).readAsBytes(), orderedEquals(bytes));
    }
  });

  test(
    'snapshot WAV export copies exact cache bytes with inner name',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'snapshot_wav_export_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final wavBytes = Uint8List.fromList(<int>[
        ...'RIFF'.codeUnits,
        for (var index = 0; index < 64; index++) (index * 17) & 0xff,
      ]);
      final cached = File(join(tempDirectory.path, 'snapshot_deadbeef.wav'));
      await cached.writeAsBytes(wavBytes, flush: true);

      for (final imageName in <String>['direct.z80', 'nested-state.sna']) {
        final exportPath = await stageWavForExport(
          cachedWavPath: cached.path,
          imageFileName: imageName,
          temporaryDirectoryPath: tempDirectory.path,
        );
        expect(
          basename(exportPath),
          '${imageName.substring(0, imageName.lastIndexOf('.'))}.wav',
        );
        expect(await File(exportPath).readAsBytes(), orderedEquals(wavBytes));
        expect(exportPath, isNot(cached.path));
      }
    },
  );

  test('snapshot formats remain excluded from ZX80 and ZX81', () {
    final bytes = Uint8List.fromList([1]);
    for (final model in [ZxModel.zx80, ZxModel.zx81]) {
      expect(
        () => resolveTapeImage((bytes, 'game.z80'), model: model),
        throwsFormatException,
      );
      expect(
        () => resolveTapeImage((bytes, 'game.sna'), model: model),
        throwsFormatException,
      );
    }
  });

  test('ZIP resolution ignores unsafe member paths', () {
    final unsafe = Uint8List.fromList([9]);
    final safe = Uint8List.fromList([1, 2]);
    final archive = Archive()
      ..addFile(ArchiveFile('../escape.z80', unsafe.length, unsafe))
      ..addFile(ArchiveFile('/absolute.sna', unsafe.length, unsafe))
      ..addFile(ArchiveFile(r'C:\escape.z80', unsafe.length, unsafe))
      ..addFile(ArchiveFile(r'nested\..\escape.sna', unsafe.length, unsafe))
      ..addFile(ArchiveFile('safe/game.z80', safe.length, safe));
    final image = resolveTapeImage((
      Uint8List.fromList(ZipEncoder().encode(archive)),
      'snapshots.zip',
    ), model: ZxModel.zxSpectrum);

    expect(image.innerPath, 'safe/game.z80');
    expect(image.bytes, safe);
  });

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
