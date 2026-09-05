import 'package:zx_tape_player/models/software_model.dart';

bool canScrollMediaCarousel({
  required Duration position,
  required int optionCount,
  required bool loading,
  required bool playbackCompleted,
}) =>
    optionCount > 1 &&
    !loading &&
    (position == Duration.zero || playbackCompleted);

bool shouldPrepareSelectedMedia({
  required Duration position,
  required bool hasBlocks,
}) => position == Duration.zero || !hasBlocks;

/// Owns the shared file index used by carousel display and player actions.
class TapePlayerMediaSelection {
  TapePlayerMediaSelection(SoftwareModel software)
    : files = software.tapeFiles,
      _currentIndex = software.tapeFiles.isEmpty ? -1 : 0;

  final List<String> files;
  int _currentIndex;

  int get currentIndex => _currentIndex;

  String get currentFile {
    if (_currentIndex < 0) {
      throw StateError('Cannot select media from an empty option list');
    }
    return files[_currentIndex];
  }

  void select(int index) {
    RangeError.checkValidIndex(index, files, 'index');
    _currentIndex = index;
  }
}
