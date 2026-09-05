import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/models/software_model.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/media_selection.dart';

void main() {
  group('carousel availability', () {
    test('is available at the beginning with multiple options', () {
      expect(
        canScrollMediaCarousel(
          position: Duration.zero,
          optionCount: 2,
          loading: false,
          playbackCompleted: false,
        ),
        isTrue,
      );
    });

    test('is locked while playback is in progress', () {
      expect(
        canScrollMediaCarousel(
          position: const Duration(seconds: 1),
          optionCount: 2,
          loading: false,
          playbackCompleted: false,
        ),
        isFalse,
      );
    });

    test('is available when playback completed at a nonzero position', () {
      expect(
        canScrollMediaCarousel(
          position: const Duration(minutes: 3),
          optionCount: 2,
          loading: false,
          playbackCompleted: true,
        ),
        isTrue,
      );
    });

    test('remains locked while loading or with one option', () {
      expect(
        canScrollMediaCarousel(
          position: Duration.zero,
          optionCount: 2,
          loading: true,
          playbackCompleted: true,
        ),
        isFalse,
      );
      expect(
        canScrollMediaCarousel(
          position: Duration.zero,
          optionCount: 1,
          loading: false,
          playbackCompleted: true,
        ),
        isFalse,
      );
    });

    test('new selection is prepared even if the old position was nonzero', () {
      expect(
        shouldPrepareSelectedMedia(
          position: const Duration(minutes: 3),
          hasBlocks: false,
        ),
        isTrue,
      );
      expect(
        shouldPrepareSelectedMedia(
          position: const Duration(minutes: 3),
          hasBlocks: true,
        ),
        isFalse,
      );
    });
  });

  test('carousel pages and selected actions share one canonical index', () {
    final software = SoftwareModel(
      'id',
      true,
      'Title',
      null,
      null,
      null,
      null,
      null,
      null,
      <AuthorModel>[],
      <ScreenShotModel>[],
      'state.z80',
      <String>[
        'https://example.test/state.z80',
        'https://example.test/side-b.tzx',
        'https://example.test/side-a.tap',
        'https://example.test/backup.sna.zip',
      ],
    );
    final selection = TapePlayerMediaSelection(software)
      ..select(software.currentFileIndex);

    expect(selection.files, <String>[
      'https://example.test/side-b.tzx',
      'https://example.test/side-a.tap',
      'https://example.test/state.z80',
      'https://example.test/backup.sna.zip',
    ]);
    expect(selection.currentIndex, 2);
    expect(selection.currentFile, selection.files[selection.currentIndex]);
    expect(selection.currentFile, endsWith('state.z80'));

    selection.select(1);
    expect(selection.currentFile, selection.files[1]);
    expect(selection.currentFile, endsWith('side-a.tap'));
  });
}
