import 'dart:typed_data';

import 'snapshot_error.dart';

class SnapshotByteReader {
  SnapshotByteReader(Uint8List bytes, {this.label = 'snapshot'})
    : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  final String label;
  int _offset = 0;

  int get offset => _offset;
  int get length => _bytes.length;
  int get remaining => _bytes.length - _offset;
  bool get isAtEnd => _offset == _bytes.length;

  int peekU8([int relativeOffset = 0]) {
    _require(relativeOffset + 1);
    return _bytes[_offset + relativeOffset];
  }

  int readU8() {
    _require(1);
    return _bytes[_offset++];
  }

  int readU16() {
    _require(2);
    final value = _bytes[_offset] | (_bytes[_offset + 1] << 8);
    _offset += 2;
    return value;
  }

  Uint8List readBytes(int count) {
    if (count < 0) {
      throw SnapshotException(
        SnapshotErrorCode.invalidLength,
        '$label requested a negative byte count: $count',
        offset: _offset,
      );
    }
    _require(count);
    final result = Uint8List.fromList(_bytes.sublist(_offset, _offset + count));
    _offset += count;
    return result;
  }

  void skip(int count) {
    readBytes(count);
  }

  void expectEnd() {
    if (!isAtEnd) {
      throw SnapshotException(
        SnapshotErrorCode.invalidLength,
        '$label has $remaining trailing byte${remaining == 1 ? '' : 's'}',
        offset: _offset,
      );
    }
  }

  void _require(int count) {
    if (count < 0 || count > remaining) {
      throw SnapshotException(
        SnapshotErrorCode.truncatedInput,
        '$label needs $count byte${count == 1 ? '' : 's'} but only '
        '$remaining remain',
        offset: _offset,
      );
    }
  }
}
