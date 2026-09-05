import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_decoder.dart';
import 'package:zx_tape_player/snapshots/snapshot_models.dart';

import 'snapshot_fixtures.dart';

void main() {
  test(
    'semantic fixture matrix covers every required cross-layer category',
    () {
      expect(
        snapshotFixtureMatrix.map((fixture) => fixture.category).toSet(),
        SnapshotFixtureCategory.values.toSet(),
      );
      final ids = snapshotFixtureMatrix.map((fixture) => fixture.id).toList();
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'Fixture IDs must be unique',
      );
      for (final category in SnapshotFixtureCategory.values) {
        expect(
          snapshotFixtureMatrix.where(
            (fixture) => fixture.category == category,
          ),
          isNotEmpty,
          reason: '${category.name} requires at least one semantic case',
        );
      }
    },
  );

  test('supported fixture builders enumerate the admitted machine matrix', () {
    const decoder = SnapshotDecoder();
    final snapshots = [
      decoder.decode(makeZ80V1(), 'v1-raw.z80'),
      decoder.decode(makeZ80V1(compressed: true), 'v1-rle.z80'),
      decoder.decode(makeZ80Extended(version3: false), 'v2-48.z80'),
      decoder.decode(
        makeZ80Extended(version3: false, hardwareMode: 1),
        'v2-48-interface1.z80',
      ),
      decoder.decode(
        makeZ80Extended(
          version3: false,
          machine: SpectrumSnapshotMachine.spectrum128k,
        ),
        'v2-128.z80',
      ),
      decoder.decode(makeZ80Extended(), 'v3-48.z80'),
      decoder.decode(
        makeZ80Extended(machine: SpectrumSnapshotMachine.spectrum128k),
        'v3-128.z80',
      ),
      decoder.decode(makeSna48(), '48.sna'),
      decoder.decode(makeSna128(currentBank: 3), '128-normal.sna'),
      decoder.decode(makeSna128(currentBank: 2), '128-bank2.sna'),
      decoder.decode(makeSna128(currentBank: 5), '128-bank5.sna'),
    ];

    expect(snapshots, hasLength(11));
    expect(
      snapshots.where(
        (snapshot) => snapshot.machine == SpectrumSnapshotMachine.spectrum48k,
      ),
      hasLength(6),
    );
    expect(
      snapshots.where(
        (snapshot) => snapshot.machine == SpectrumSnapshotMachine.spectrum128k,
      ),
      hasLength(5),
    );
  });
}
