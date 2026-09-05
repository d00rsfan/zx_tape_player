import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

enum TapePlayerState { indexChanged, loading, idle, error }

class TapePlayerData {
  final TapePlayerState state;
  final String? message;
  final TapeConversionMessage? error;
  final String filePath;
  final List<TapeBlockInfo>? blocks;
  final List<TapeConversionMessage> warnings;
  final TapeMediaKind? mediaKind;

  TapePlayerData(
    this.state,
    this.filePath, {
    this.message,
    this.error,
    this.blocks,
    this.warnings = const [],
    this.mediaKind,
  });
}
