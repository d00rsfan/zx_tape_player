import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/snapshots/snapshot_decoder.dart';
import 'package:zx_tape_player/snapshots/snapshot_error.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_restore_planner.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';

import 'snapshot_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const decoder = SnapshotDecoder();
  const planner = SnapshotRestorePlanner();
  late SnapshotAssetBundle assets;

  setUpAll(() async {
    assets = SnapshotAssetBundle(
      receiver48Tap: await _asset(
        SnapshotReceiverManifest.receiver48.assetPath,
      ),
      receiver128Tap: await _asset(
        SnapshotReceiverManifest.receiver128.assetPath,
      ),
      registerBlob: await _asset(SnapshotReceiverManifest.registerAssetPath),
    );
  });

  group('register patching', () {
    test('matches the complete representative Z80 golden blob', () {
      final snapshot = decoder.decode(
        makeZ80V1(border: 6, rHigh: true, interruptMode: 2),
        'state.z80',
      );
      final patched = const SnapshotRegisterPatcher().patch(
        assets.registerBlob,
        snapshot.registers,
      );

      expect(
        patched,
        _hex(
          '01 34 12 c5 01 18 17 c5 3e 06 d3 fe 01 12 11 11 14 13 '
          '21 16 15 f1 d9 08 01 78 56 11 f0 de 21 bc 9a dd 21 1c '
          '1b fd 21 1a 19 3e a1 ed 4f 3e 3f ed 47 f1 31 '
          '00 90 ed 5e fb c3 67 45',
        ),
      );
    });

    test('uses direct SNA border/IFF/R values for 48K and 128K', () {
      for (final fixture in [
        makeSna48(border: 7, interruptsEnabled: false),
        makeSna128(border: 7, interruptsEnabled: false),
      ]) {
        final snapshot = decoder.decode(fixture, 'state.sna');
        final patched = const SnapshotRegisterPatcher().patch(
          assets.registerBlob,
          snapshot.registers,
        );
        final offsets = SnapshotReceiverManifest.registerOffsets;
        expect(patched[offsets['border']!], 7);
        expect(patched[offsets['interruptEnable']!], 0xf3);
        expect(patched[offsets['r']!], 0xa1);
        expect(
          SnapshotRegisterPatcher.restoredRefreshRegister(
            patched[offsets['r']!],
          ),
          0xaa,
        );
      }
    });

    test('pre-compensates R low bits across refresh-counter wrap', () {
      for (var savedR = 0; savedR <= 0xff; savedR++) {
        final encoded = SnapshotRegisterPatcher.encodeRefreshRegister(savedR);
        expect(
          SnapshotRegisterPatcher.restoredRefreshRegister(encoded),
          savedR,
        );
        expect(encoded & 0x80, savedR & 0x80);
      }
    });
  });

  group('address ranges', () {
    test('overlap is half-open and distinguishes bank tags', () {
      final range = _range(0x4000, [1, 2, 3], bank: 1);
      expect(range.overlaps(0x4001, 0x4004, otherBank: 1), isTrue);
      expect(range.overlaps(0x4003, 0x4004, otherBank: 1), isFalse);
      expect(range.overlaps(0x4000, 0x4003, otherBank: 2), isFalse);
    });

    test('splits adjacent, interior, empty, and address-space boundaries', () {
      final range = _range(0xfffc, [1, 2, 3, 4]);
      expect(range.splitAt(0xfffc), hasLength(1));
      expect(range.splitAt(0x10000), hasLength(1));
      final split = range.splitAt(0xfffe);
      expect(split.map((piece) => piece.start), [0xfffc, 0xfffe]);
      expect(split.map((piece) => piece.data), [
        [1, 2],
        [3, 4],
      ]);
      expect(_range(0x10000, const []).isEmpty, isTrue);
    });

    test('compacts adjacency and gives overlapping later bytes priority', () {
      final result = compactSnapshotRanges([
        _range(0x4000, [1, 1, 1, 1]),
        _range(0x4004, [2, 2]),
        _range(0x4002, [9, 9]),
        _range(0xc000, [3], bank: 1),
      ]);

      expect(result, hasLength(2));
      expect(result[0].start, 0x4000);
      expect(result[0].data, [1, 1, 9, 9, 2, 2]);
      expect(result[1].bank, 1);
    });
  });

  group('relocation and planning', () {
    test('patches both receivers for every profile and fixes TAP checksum', () {
      final fixtures = [
        (makeZ80V1(), 'state.z80'),
        (makeSna128(currentBank: 3), 'state.sna'),
      ];
      for (final fixture in fixtures) {
        final snapshot = decoder.decode(fixture.$1, fixture.$2);
        final layout = SnapshotReceiverManifest.layoutFor(snapshot.machine);
        final original = assets.receiverFor(snapshot.machine);
        expect(
          [
            original[layout.rawTapOffsetForAddress(
              layout.leaderMaxFirstAddress,
            )],
            original[layout.rawTapOffsetForAddress(
              layout.leaderMinCompareFirstAddress,
            )],
            original[layout.rawTapOffsetForAddress(
              layout.leaderMaxSecondAddress,
            )],
            original[layout.rawTapOffsetForAddress(
              layout.syncMinCompareAddress,
            )],
            original[layout.rawTapOffsetForAddress(
              layout.leaderMinCompareSecondAddress,
            )],
            original[layout.rawTapOffsetForAddress(layout.miniSyncMaxAddress)],
          ],
          [0x0c, 0x06, 0x0c, 0x0a, 0x06, 0xc8],
          reason: '${fixture.$2} acquisition patch manifest',
        );
        for (final profile in SnapshotTurboProfiles.values) {
          final plan = planner.createPlan(
            snapshot,
            assets,
            turboProfile: profile,
          );
          expect(
            plan.receiverTap[layout.rawTapOffsetForAddress(
              layout.bitLoopMaxAddress,
            )],
            SnapshotTiming.bitLoopMax,
            reason: '${fixture.$2} ${profile.label}',
          );
          expect(
            plan.receiverTap[layout.rawTapOffsetForAddress(
              layout.bitOneThresholdAddress,
            )],
            profile.bitOneThreshold,
            reason: '${fixture.$2} ${profile.label}',
          );
          expect(
            [
              plan.receiverTap[layout.rawTapOffsetForAddress(
                layout.leaderMaxFirstAddress,
              )],
              plan.receiverTap[layout.rawTapOffsetForAddress(
                layout.leaderMinCompareFirstAddress,
              )],
              plan.receiverTap[layout.rawTapOffsetForAddress(
                layout.leaderMaxSecondAddress,
              )],
              plan.receiverTap[layout.rawTapOffsetForAddress(
                layout.syncMinCompareAddress,
              )],
              plan.receiverTap[layout.rawTapOffsetForAddress(
                layout.leaderMinCompareSecondAddress,
              )],
              plan.receiverTap[layout.rawTapOffsetForAddress(
                layout.miniSyncMaxAddress,
              )],
            ],
            [
              profile.receiverLeaderMax,
              profile.receiverLeaderMinCompare,
              profile.receiverLeaderMax,
              profile.receiverSyncMinCompare,
              profile.receiverLeaderMinCompare,
              SnapshotTiming.receiverMiniSyncMax,
            ],
            reason: '${fixture.$2} ${profile.label} acquisition constants',
          );
          expect(_secondTapBlockChecksumIsValid(plan.receiverTap), isTrue);
        }
      }
    });

    test('finds safe fixed zero RAM below the receiver upper region', () {
      final ram = make48kRam();
      ram.fillRange(6912, 6912 + 500, 0);
      final snapshot = decoder.decode(makeZ80V1(ram: ram), 'auto.z80');
      final plan = planner.createPlan(
        snapshot,
        assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
      );

      expect(plan.loaderStart, SnapshotRestorePlanner.afterScreen);
      expect(plan.usedScreenFallback, isFalse);
      expect(
        plan.blocks
            .skip(1)
            .take(plan.blocks.length - 2)
            .any(
              (block) => block.overlaps(
                plan.loaderStart,
                plan.loaderStart + plan.relocatedWorkingLength,
              ),
            ),
        isFalse,
      );
    });

    test('keeps relocation away from PC, SP, and the IM 2 vector table', () {
      final ram = make48kRam()..fillRange(0, 48 * 1024, 0x33);
      for (final address in [0x6000, 0x7000, 0x8000, 0x9000]) {
        ram.fillRange(address - 0x4000, address - 0x4000 + 0x200, 0);
      }
      final bytes = Uint8List.fromList(makeZ80V1(ram: ram, interruptMode: 2));
      bytes[6] = 0x00;
      bytes[7] = 0x61;
      bytes[8] = 0x00;
      bytes[9] = 0x71;
      bytes[10] = 0x80;

      final plan = planner.createPlan(
        decoder.decode(bytes, 'critical-ranges.z80'),
        assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
      );

      expect(plan.loaderStart, 0x9000);
      expect(plan.usedScreenFallback, isFalse);
    });

    test('rejects a screen fallback that would overwrite the resume PC', () {
      final ram = make48kRam()..fillRange(0, 48 * 1024, 0x33);
      final bytes = Uint8List.fromList(makeZ80V1(ram: ram));
      bytes[6] = 0x00;
      bytes[7] = 0x51;

      expect(
        () => planner.createPlan(
          decoder.decode(bytes, 'unsafe-fallback.z80'),
          assets,
          turboProfile: SnapshotTurboProfiles.speed10x,
        ),
        throwsCode(SnapshotErrorCode.invalidRestorePlan),
      );
    });

    test(
      'rejects live receiver and banked zero candidates, then falls back',
      () {
        final fixed = make48kRam()..fillRange(0, 48 * 1024, 0x33);
        final layout = SnapshotReceiverManifest.receiver48;
        fixed.fillRange(
          layout.totalStart - 0x4000,
          layout.totalStart - 0x4000 + 500,
          0,
        );
        final location = planner.findRelocation(
          fixed,
          layout,
          requiredLength: 411,
        );
        expect(location, SnapshotRestorePlanner.fallbackLoaderStart);

        final snapshot128 = decoder.decode(
          makeSna128(currentBank: 3),
          'banked.sna',
        );
        final plan128 = planner.createPlan(
          snapshot128,
          assets,
          turboProfile: SnapshotTurboProfiles.speed10x,
        );
        expect(plan128.loaderStart, SnapshotRestorePlanner.fallbackLoaderStart);
      },
    );

    test('48K plan matches the ordered screen/staging/final golden', () {
      final ram = make48kRam()..fillRange(0, 48 * 1024, 0x33);
      final snapshot = decoder.decode(makeZ80V1(ram: ram), 'fallback.z80');
      final plan = planner.createPlan(
        snapshot,
        assets,
        turboProfile: SnapshotTurboProfiles.speed10x,
      );

      expect(plan.loaderStart, 0x5000);
      expect(plan.registerCodeStart, 0x5190);
      expect(plan.stagingAddress, 0x50c8);
      expect(plan.blocks.map((block) => block.name), [
        'Screen',
        'Fixed RAM',
        'Final receiver overwrite',
      ]);
      expect(
        plan.blocks.map((block) => block.start),
        snapshotGolden48FallbackStarts,
      );
      expect(
        plan.blocks.map((block) => block.data.length),
        snapshotGolden48FallbackLengths,
      );
      expect(plan.blocks.last.executionAddress, 0x5190);
      plan.validate();
    });

    test(
      '128K plans restore each unique bank and preserve every current bank',
      () {
        for (var currentBank = 0; currentBank < 8; currentBank++) {
          final snapshot = decoder.decode(
            makeSna128(currentBank: currentBank),
            'bank$currentBank.sna',
          );
          final plan = planner.createPlan(
            snapshot,
            assets,
            turboProfile: SnapshotTurboProfiles.speed10x,
          );
          expect(
            plan.blocks
                .where((block) => block.bank != null)
                .map((block) => block.bank),
            [1, 3, 4, 6, 7],
          );
          expect(plan.finalOut7ffd & 7, currentBank);
          expect(plan.blocks.last.start, 0xbf38);
          expect(plan.blocks.last.end, 0xc000);
          plan.validate();
        }
      },
    );

    test(
      'invariants reject duplicate writes and an early execution transfer',
      () {
        final valid = planner.createPlan(
          decoder.decode(makeZ80V1(), 'valid.z80'),
          assets,
          turboProfile: SnapshotTurboProfiles.speed10x,
        );
        final duplicate = SnapshotRestorePlan(
          snapshot: valid.snapshot,
          turboProfile: valid.turboProfile,
          layout: valid.layout,
          loaderStart: valid.loaderStart,
          registerCodeStart: valid.registerCodeStart,
          stagingAddress: valid.stagingAddress,
          relocatedWorkingLength: valid.relocatedWorkingLength,
          receiverTap: valid.receiverTap,
          expectedFixedRam: valid.expectedFixedRam,
          blocks: [valid.blocks.first, ...valid.blocks],
          usedScreenFallback: valid.usedScreenFallback,
        );
        expect(
          duplicate.validate,
          throwsCode(SnapshotErrorCode.invalidRestorePlan),
        );

        final early = valid.blocks.first.copyWith(
          executionAddress: valid.registerCodeStart,
        );
        final badExecution = SnapshotRestorePlan(
          snapshot: valid.snapshot,
          turboProfile: valid.turboProfile,
          layout: valid.layout,
          loaderStart: valid.loaderStart,
          registerCodeStart: valid.registerCodeStart,
          stagingAddress: valid.stagingAddress,
          relocatedWorkingLength: valid.relocatedWorkingLength,
          receiverTap: valid.receiverTap,
          expectedFixedRam: valid.expectedFixedRam,
          blocks: [early, ...valid.blocks.skip(1)],
          usedScreenFallback: valid.usedScreenFallback,
        );
        expect(
          badExecution.validate,
          throwsCode(SnapshotErrorCode.invalidRestorePlan),
        );
      },
    );
  });
}

SnapshotMemoryRange _range(int start, List<int> data, {int? bank}) =>
    SnapshotMemoryRange(
      name: 'range',
      start: start,
      data: Uint8List.fromList(data),
      kind: bank == null
          ? SnapshotRangeKind.fixedRam
          : SnapshotRangeKind.bankedRam,
      bank: bank,
    );

Uint8List _hex(String value) => Uint8List.fromList(
  value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => int.parse(part, radix: 16))
      .toList(),
);

Future<Uint8List> _asset(String path) async {
  final data = await rootBundle.load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

bool _secondTapBlockChecksumIsValid(Uint8List tap) {
  final firstLength = tap[0] | (tap[1] << 8);
  final secondLengthOffset = 2 + firstLength;
  final length = tap[secondLengthOffset] | (tap[secondLengthOffset + 1] << 8);
  final start = secondLengthOffset + 2;
  var checksum = 0;
  for (var index = start; index < start + length - 1; index++) {
    checksum ^= tap[index];
  }
  return checksum == tap[start + length - 1];
}

Matcher throwsCode(SnapshotErrorCode code) => throwsA(
  isA<SnapshotException>().having((error) => error.code, 'code', code),
);
