enum SnapshotErrorCode {
  invalidExtension,
  emptyInput,
  truncatedInput,
  invalidLength,
  invalidCompression,
  unsupportedHardware,
  invalidPage,
  duplicatePage,
  missingPage,
  invalidStackPointer,
  invalidAsset,
  invalidRestorePlan,
  invalidTurboBlock,
}

class SnapshotException implements Exception {
  const SnapshotException(this.code, this.message, {this.offset});

  final SnapshotErrorCode code;
  final String message;
  final int? offset;

  @override
  String toString() {
    final at = offset == null ? '' : ' at byte $offset';
    return 'SnapshotException(${code.name}$at): $message';
  }
}
