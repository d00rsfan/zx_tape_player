import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

enum TapePlayerState { IndexChanged, Loading, Idle, Error }

class TapePlayerData {
  final TapePlayerState state;
  final String? message;
  final String filePath;
  final List<TapeBlockInfo>? blocks;

  TapePlayerData(this.state, this.filePath, {this.message, this.blocks});
}
