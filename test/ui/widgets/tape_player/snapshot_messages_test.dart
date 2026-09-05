import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/snapshot_messages.dart';

void main() {
  String lookup(String key) => <String, String>{
    'snapshot_warning_trdos':
        'TR-DOS paging is not restored; playback can continue.',
    'snapshot_warning_detail': 'Snapshot limitation: %s',
    'snapshot_error_unsupported': 'Unsupported snapshot: %s',
    'snapshot_error_internal': 'Snapshot conversion failed internally: %s',
    'snapshot_error_malformed': 'Invalid snapshot: %s',
    'snapshot_error_byte_offset': '(byte %s)',
  }[key]!;

  test('maps TR-DOS warning to its localized continuation message', () {
    const warning = TapeConversionMessage(
      code: 'trDosRomNotRestored',
      message: 'core detail must not replace the localized warning',
    );

    expect(
      snapshotWarningText(warning, lookup),
      'TR-DOS paging is not restored; playback can continue.',
    );
  });

  test('keeps malformed snapshot detail and byte offset visible', () {
    const error = TapeConversionMessage(
      code: 'truncatedInput',
      message: 'Z80 additional header is truncated',
      offset: 30,
    );

    expect(
      snapshotErrorText(error, lookup),
      'Invalid snapshot: Z80 additional header is truncated (byte 30)',
    );
  });

  test('distinguishes unsupported hardware and internal asset failures', () {
    expect(
      snapshotErrorText(
        const TapeConversionMessage(
          code: 'unsupportedHardware',
          message: 'Z80 +3 mode is unsupported',
        ),
        lookup,
      ),
      'Unsupported snapshot: Z80 +3 mode is unsupported',
    );
    expect(
      snapshotErrorText(
        const TapeConversionMessage(
          code: 'invalidAsset',
          message: 'receiver hash mismatch',
        ),
        lookup,
      ),
      'Snapshot conversion failed internally: receiver hash mismatch',
    );
  });
}
