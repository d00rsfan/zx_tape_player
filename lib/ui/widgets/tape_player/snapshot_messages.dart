import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/utils/extensions.dart';

typedef SnapshotTranslationLookup = String Function(String key);

String snapshotWarningText(
  TapeConversionMessage warning,
  SnapshotTranslationLookup translate,
) {
  if (warning.code == 'trDosRomNotRestored') {
    return translate('snapshot_warning_trdos');
  }
  return translate('snapshot_warning_detail').format([warning.message]);
}

String snapshotErrorText(
  TapeConversionMessage error,
  SnapshotTranslationLookup translate,
) {
  final detail = error.offset == null
      ? error.message
      : '${error.message} '
            '${translate('snapshot_error_byte_offset').format([error.offset])}';
  final key = switch (error.code) {
    'unsupportedHardware' => 'snapshot_error_unsupported',
    'invalidAsset' ||
    'invalidRestorePlan' ||
    'invalidTurboBlock' => 'snapshot_error_internal',
    _ => 'snapshot_error_malformed',
  };
  return translate(key).format([detail]);
}
