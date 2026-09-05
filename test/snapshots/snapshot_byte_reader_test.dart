import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_byte_reader.dart';
import 'package:zx_tape_player/snapshots/snapshot_error.dart';

void main() {
  test('reads little-endian primitives and copied slices', () {
    final source = Uint8List.fromList([1, 2, 3, 4]);
    final reader = SnapshotByteReader(source);
    expect(reader.peekU8(), 1);
    expect(reader.readU8(), 1);
    expect(reader.readU16(), 0x0302);
    final slice = reader.readBytes(1)..[0] = 99;
    expect(slice, [99]);
    expect(source.last, 4);
    expect(reader.isAtEnd, isTrue);
    expect(reader.expectEnd, returnsNormally);
  });

  test('reports checked truncation and invalid counts with offsets', () {
    final reader = SnapshotByteReader(
      Uint8List.fromList([1]),
      label: 'fixture',
    );
    expect(reader.readU8(), 1);
    expect(
      reader.readU16,
      throwsA(
        isA<SnapshotException>()
            .having(
              (error) => error.code,
              'code',
              SnapshotErrorCode.truncatedInput,
            )
            .having((error) => error.offset, 'offset', 1),
      ),
    );
    expect(
      () => reader.readBytes(-1),
      throwsA(
        isA<SnapshotException>().having(
          (error) => error.code,
          'code',
          SnapshotErrorCode.invalidLength,
        ),
      ),
    );
  });

  test('expectEnd rejects trailing bytes', () {
    final reader = SnapshotByteReader(Uint8List.fromList([1, 2]));
    reader.readU8();
    expect(
      reader.expectEnd,
      throwsA(
        isA<SnapshotException>().having((error) => error.offset, 'offset', 1),
      ),
    );
  });
}
