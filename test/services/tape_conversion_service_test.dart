import 'dart:async';
import 'dart:io' hide BytesBuilder;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

void main() {
  test('direct TAP converts through the production isolate worker', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'zx_tap_conversion_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final output = File(join(tempDirectory.path, 'converted.wav'));
    final progressPort = ReceivePort();
    final progress = <int>[];
    final progressComplete = Completer<void>();
    final subscription = progressPort.listen((message) {
      if (message is! int) return;
      progress.add(message);
      if (message == 100 && !progressComplete.isCompleted) {
        progressComplete.complete();
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      progressPort.close();
    });

    final response = await compute(
      convertTapeImage,
      TapeConversionRequest(
        tapeBytes: _buildTap(),
        fileName: 'direct.tap',
        outputPath: output.path,
        progressPort: progressPort.sendPort,
        audioFilterIndex: AudioFilterType.bassBoost.index,
      ),
    );
    await progressComplete.future.timeout(const Duration(seconds: 1));

    expect(response.blocks, isNotEmpty);
    expect(response.warnings, isEmpty);
    expect(progress, contains(100));
    expect(await output.length(), greaterThan(44));
    expect(await output.openRead(0, 4).single, equals('RIFF'.codeUnits));
  });

  test('ZX81 .81 is byte-for-byte equivalent to .p audio', () async {
    final bytes = _buildPFile(160);

    final (_, pWav) = await _convert(bytes, 'demo.p');
    final (_, aliasWav) = await _convert(bytes, 'demo.81');

    expect(aliasWav, orderedEquals(pWav));
  });

  test('ZX81 .p81 preserves its embedded tape name', () async {
    final data = _buildPFile(160);
    const name = <int>[0x39, 0x2a, 0x38, 0xb9]; // TEST, terminated by bit 7.
    final bytes = Uint8List.fromList(<int>[...name, ...data, 0xaa, 0x55]);

    expect(await isTapeImageSupported(bytes, 'host-name.p81'), isTrue);
    final (response, wav) = await _convert(bytes, 'host-name.p81');

    expect(response.blocks.first.title, 'TEST');
    expect(response.blocks.first.dataLength, data.length);
    expect(_decodeRawSinclairWav(wav), <int>[...name, ...data]);
  });

  test('ZX80 .o and .80 aliases emit data without a filename', () async {
    final memoryImage = _buildOFile(80);
    final bytes = Uint8List.fromList(<int>[...memoryImage, 0xaa, 0x55]);

    expect(await isTapeImageSupported(bytes, 'demo.o'), isTrue);
    expect(await isTapeImageSupported(bytes, 'demo.80'), isTrue);
    final (oResponse, oWav) = await _convert(bytes, 'demo.o');
    final (_, aliasWav) = await _convert(bytes, 'demo.80');

    expect(aliasWav, orderedEquals(oWav));
    expect(oResponse.blocks.first.title, 'demo');
    expect(oResponse.blocks.first.dataLength, memoryImage.length);
    expect(_decodeRawSinclairWav(oWav), orderedEquals(memoryImage));
  });

  test('remote-style P and O ZIP archives convert end to end', () async {
    final fixtures = <(String, String, Uint8List)>[
      ('ZXOKO-BAN.p.zip', 'ZXOKO-BAN.p', _buildPFile(160)),
      (
        'ComplexMathsAddition(1K).o.zip',
        'Complex Maths Addition.o',
        _buildOFile(80),
      ),
    ];

    for (final fixture in fixtures) {
      final archive = Archive()
        ..addFile(ArchiveFile(fixture.$2, fixture.$3.length, fixture.$3));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(await isTapeImageSupported(zipBytes, fixture.$1), isTrue);
      final (response, wav) = await _convert(zipBytes, fixture.$1);

      expect(response.blocks, isNotEmpty);
      expect(wav.sublist(0, 4), orderedEquals('RIFF'.codeUnits));
    }
  });

  test('remote-style generalized TZX archive converts end to end', () async {
    final tzxBytes = _buildGeneralizedTzx();
    final archive = Archive()
      ..addFile(ArchiveFile('Trader(Trimp).tzx', tzxBytes.length, tzxBytes));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(
      await isTapeImageSupported(zipBytes, 'Trader(Trimp).tzx.zip'),
      isTrue,
    );
    final (response, wav) = await _convert(zipBytes, 'Trader(Trimp).tzx.zip');

    expect(response.blocks.first.typeName, 'Data');
    expect(response.blocks.first.dataLength, 8);
    expect(response.blocks.first.timeOffset, Duration.zero);
    expect(response.blocks.first.sampleOffset, 0);
    expect(response.warnings, isEmpty);
    expect(wav.sublist(0, 4), orderedEquals('RIFF'.codeUnits));
    expect(wav[44], greaterThanOrEqualTo(128));
  });

  test('truncated ZX80 memory images are rejected', () async {
    final bytes = _buildOFile(80);
    bytes[10] = 0xff;
    bytes[11] = 0x7f;

    expect(await isTapeImageSupported(bytes, 'broken.o'), isFalse);
    expect(await isTapeImageSupported(bytes, 'broken.80'), isFalse);
  });
}

Future<(TapeConversionResponse, Uint8List)> _convert(
  Uint8List bytes,
  String fileName,
) async {
  final tempDirectory = await Directory.systemTemp.createTemp(
    'zx_raw_conversion_test_',
  );
  addTearDown(() => tempDirectory.delete(recursive: true));
  final output = File(join(tempDirectory.path, 'converted.wav'));
  final progressPort = ReceivePort();
  final subscription = progressPort.listen((_) {});

  final response = await compute(
    convertTapeImage,
    TapeConversionRequest(
      tapeBytes: bytes,
      fileName: fileName,
      outputPath: output.path,
      progressPort: progressPort.sendPort,
      audioFilterIndex: AudioFilterType.none.index,
    ),
  );
  await subscription.cancel();
  progressPort.close();
  return (response, await output.readAsBytes());
}

Uint8List _buildTap() {
  // Two valid two-byte TAP blocks. Each block is prefixed by its little-endian
  // length and ends in the XOR checksum of its preceding byte.
  return Uint8List.fromList([2, 0, 0x00, 0x00, 2, 0, 0xff, 0xff]);
}

Uint8List _buildGeneralizedTzx() {
  const maximumPulsesPerSymbol = 19;
  final block = BytesBuilder();
  _addUint16(block, 100); // Pause after the generalized data block, in ms.
  _addUint32(block, 0); // No pilot/sync symbols.
  block.addByte(0); // Maximum pulses per pilot symbol (unused).
  block.addByte(0); // Pilot alphabet size (unused).
  _addUint32(block, 8); // Eight data symbols, or one byte.
  block.addByte(maximumPulsesPerSymbol);
  block.addByte(2); // Binary data-symbol alphabet.

  final zeroPulses = <int>[530, 520, 530, 520, 530, 520, 530, 520, 4689];
  final onePulses = <int>[
    for (var i = 0; i < 9; i++) ...<int>[530, 520],
    4689,
  ];
  _addGeneralizedSymbol(block, zeroPulses, maximumPulsesPerSymbol);
  _addGeneralizedSymbol(block, onePulses, maximumPulsesPerSymbol);
  block.addByte(0x41); // Eight symbol indexes: 0,1,0,0,0,0,0,1.

  final blockBytes = block.toBytes();
  final tzx = BytesBuilder()
    ..add('ZXTape!'.codeUnits)
    ..addByte(0x1a)
    ..add(<int>[1, 20])
    ..addByte(0x19);
  _addUint32(tzx, blockBytes.length);
  tzx.add(blockBytes);
  return tzx.toBytes();
}

void _addGeneralizedSymbol(
  BytesBuilder block,
  List<int> pulses,
  int maximumPulses,
) {
  block.addByte(0); // Toggle the signal level for the first pulse.
  for (var index = 0; index < maximumPulses; index++) {
    _addUint16(block, index < pulses.length ? pulses[index] : 0);
  }
}

void _addUint16(BytesBuilder target, int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  target.add(data.buffer.asUint8List());
}

void _addUint32(BytesBuilder target, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  target.add(data.buffer.asUint8List());
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

Uint8List _buildOFile(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (i * 29 + 3) & 0xff;
  }
  final eLine = 0x4000 + length;
  bytes[10] = eLine & 0xff;
  bytes[11] = eLine >> 8;
  bytes[length - 1] = 0x80;
  return bytes;
}

/// Decodes the square-wave form used by ZX80 and ZX81 back into bytes by
/// counting the four pulses for a zero and nine pulses for a one.
List<int> _decodeRawSinclairWav(Uint8List wav) {
  final samples = wav.sublist(44);
  const bitEndLowRun = 26;
  final bits = <int>[];
  var pulseCount = 0;
  var lowRun = 0;
  var wasHigh = false;

  void closeBit() {
    expect(pulseCount, anyOf(4, 9));
    bits.add(pulseCount == 9 ? 1 : 0);
    pulseCount = 0;
  }

  for (final sample in samples) {
    final high = sample >= 128;
    if (high) {
      if (!wasHigh) {
        if (lowRun >= bitEndLowRun && pulseCount > 0) closeBit();
        pulseCount++;
      }
      lowRun = 0;
    } else {
      lowRun++;
    }
    wasHigh = high;
  }
  if (pulseCount > 0) closeBit();

  expect(bits.length % 8, 0);
  final bytes = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var value = 0;
    for (var j = 0; j < 8; j++) {
      value = (value << 1) | bits[i + j];
    }
    bytes.add(value);
  }
  return bytes;
}
