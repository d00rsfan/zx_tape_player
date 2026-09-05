import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/models/media_option_ordering.dart';
import 'package:zx_tape_player/models/software_model.dart';

void main() {
  test('recognizes only explicit snapshot suffixes case-insensitively', () {
    for (final option in <String>[
      'game.z80',
      'GAME.SNA',
      'https://example.test/Game.Z80.ZIP',
      'https://example.test/Game.sNa.zIp?download=1',
    ]) {
      expect(isExplicitSnapshotMediaOption(option), isTrue, reason: option);
    }
    for (final option in <String>[
      'game.tap',
      'game.tzx.zip',
      'https://example.test/GENERIC.ZIP',
      'game.z80.backup',
    ]) {
      expect(isExplicitSnapshotMediaOption(option), isFalse, reason: option);
    }
  });

  test('stably moves direct and zipped snapshots after all other media', () {
    final options = <String>[
      'first.z80',
      'first.tap',
      'second.SNA.ZIP',
      'generic.zip',
      'first.tap',
      'third.Z80.ZIP',
      'second.tzx',
    ];

    final ordered = orderMediaOptionsForCarousel(options);

    expect(ordered, <String>[
      'first.tap',
      'generic.zip',
      'first.tap',
      'second.tzx',
      'first.z80',
      'second.SNA.ZIP',
      'third.Z80.ZIP',
    ]);
    expect(() => ordered.add('later.tap'), throwsUnsupportedError);
  });

  test('retains source order when every option belongs to one group', () {
    expect(
      orderMediaOptionsForCarousel(<String>['b.tap', 'a.tzx', 'c.zip']),
      <String>['b.tap', 'a.tzx', 'c.zip'],
    );
    expect(
      orderMediaOptionsForCarousel(<String>['b.sna', 'a.z80.zip', 'c.Z80']),
      <String>['b.sna', 'a.z80.zip', 'c.Z80'],
    );
  });

  test('model owns its order and keeps a moved snapshot selected by name', () {
    final source = <String>[
      'https://example.test/state.z80',
      'https://example.test/loader.tap',
    ];
    final software = _software(files: source, currentFileName: 'state.z80');

    source
      ..clear()
      ..add('https://example.test/replacement.tzx');

    expect(software.tapeFiles, <String>[
      'https://example.test/loader.tap',
      'https://example.test/state.z80',
    ]);
    expect(software.currentFileIndex, 1);
    expect(
      software.tapeFiles[software.currentFileIndex],
      endsWith('state.z80'),
    );
  });
}

SoftwareModel _software({
  required List<String> files,
  String? currentFileName,
}) => SoftwareModel(
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
  currentFileName,
  files,
);
