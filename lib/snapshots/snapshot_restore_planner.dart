import 'dart:typed_data';

import 'snapshot_error.dart';
import 'snapshot_models.dart';
import 'snapshot_receiver_manifest.dart';
import 'snapshot_timing.dart';

enum SnapshotRangeKind {
  screen,
  fixedRam,
  bankedRam,
  receiver,
  staging,
  finalOverwrite,
}

/// An immutable half-open Spectrum address range tagged with its paging bank.
class SnapshotMemoryRange {
  SnapshotMemoryRange({
    required this.name,
    required this.start,
    required Uint8List data,
    required this.kind,
    this.bank,
    this.executionAddress,
  }) : data = Uint8List.fromList(data) {
    if (start < 0 || start > addressSpaceSize) {
      throw ArgumentError.value(start, 'start', 'Outside Z80 address space');
    }
    if (end > addressSpaceSize) {
      throw ArgumentError.value(end, 'data', 'Range exceeds Z80 address space');
    }
    if (bank != null && (bank! < 0 || bank! > 7)) {
      throw ArgumentError.value(bank, 'bank', 'RAM bank must be 0 through 7');
    }
    if (executionAddress != null &&
        (executionAddress! < 0 || executionAddress! > 0xffff)) {
      throw ArgumentError.value(
        executionAddress,
        'executionAddress',
        'Outside Z80 address space',
      );
    }
  }

  static const int addressSpaceSize = 0x10000;

  final String name;
  final int start;
  final Uint8List data;
  final SnapshotRangeKind kind;
  final int? bank;
  final int? executionAddress;

  int get end => start + data.length;
  bool get isEmpty => data.isEmpty;

  bool overlaps(int otherStart, int otherEnd, {int? otherBank}) {
    if (otherStart > otherEnd) {
      throw ArgumentError('Range end precedes its start');
    }
    if (bank != otherBank) return false;
    return end > otherStart && start < otherEnd;
  }

  List<SnapshotMemoryRange> splitAt(int address) {
    if (address <= start || address >= end) return [this];
    final split = address - start;
    return [
      copyWith(data: Uint8List.fromList(data.sublist(0, split))),
      copyWith(start: address, data: Uint8List.fromList(data.sublist(split))),
    ];
  }

  /// Returns the pieces before, inside, and after [rangeStart, rangeEnd].
  List<SnapshotMemoryRange> splitAround(int rangeStart, int rangeEnd) {
    if (rangeStart > rangeEnd) {
      throw ArgumentError('Range end precedes its start');
    }
    final clippedStart = rangeStart.clamp(start, end);
    final clippedEnd = rangeEnd.clamp(clippedStart, end);
    final boundaries = <int>{start, clippedStart, clippedEnd, end}.toList()
      ..sort();
    final result = <SnapshotMemoryRange>[];
    for (var index = 0; index + 1 < boundaries.length; index++) {
      final pieceStart = boundaries[index];
      final pieceEnd = boundaries[index + 1];
      if (pieceStart == pieceEnd) continue;
      result.add(
        copyWith(
          start: pieceStart,
          data: Uint8List.fromList(
            data.sublist(pieceStart - start, pieceEnd - start),
          ),
        ),
      );
    }
    return result;
  }

  SnapshotMemoryRange copyWith({
    String? name,
    int? start,
    Uint8List? data,
    SnapshotRangeKind? kind,
    int? bank,
    bool clearBank = false,
    int? executionAddress,
    bool clearExecutionAddress = false,
  }) => SnapshotMemoryRange(
    name: name ?? this.name,
    start: start ?? this.start,
    data: data ?? this.data,
    kind: kind ?? this.kind,
    bank: clearBank ? null : bank ?? this.bank,
    executionAddress: clearExecutionAddress
        ? null
        : executionAddress ?? this.executionAddress,
  );
}

/// Compacts ranges in deterministic address order. Later overlapping ranges win.
List<SnapshotMemoryRange> compactSnapshotRanges(
  Iterable<SnapshotMemoryRange> input,
) {
  final ranges = input.where((range) => !range.isEmpty).toList();
  final bankOrder = <int?>[];
  for (final range in ranges) {
    if (!bankOrder.contains(range.bank)) bankOrder.add(range.bank);
  }
  bankOrder.sort((left, right) {
    if (left == null) return -1;
    if (right == null) return 1;
    return left.compareTo(right);
  });

  final compacted = <SnapshotMemoryRange>[];
  for (final bank in bankOrder) {
    final matching = ranges.where((range) => range.bank == bank).toList();
    final boundaries = <int>{
      for (final range in matching) ...[range.start, range.end],
    }.toList()..sort();
    for (var index = 0; index + 1 < boundaries.length; index++) {
      final start = boundaries[index];
      final end = boundaries[index + 1];
      if (start == end) continue;
      SnapshotMemoryRange? winner;
      for (final candidate in matching) {
        if (candidate.start <= start && candidate.end >= end) {
          winner = candidate;
        }
      }
      if (winner == null) continue;
      final piece = winner.copyWith(
        start: start,
        data: Uint8List.fromList(
          winner.data.sublist(start - winner.start, end - winner.start),
        ),
      );
      if (compacted.isNotEmpty) {
        final previous = compacted.last;
        if (previous.end == piece.start &&
            previous.bank == piece.bank &&
            previous.kind == piece.kind &&
            previous.executionAddress == null &&
            piece.executionAddress == null) {
          compacted[compacted.length - 1] = SnapshotMemoryRange(
            name: previous.name,
            start: previous.start,
            data: Uint8List.fromList([...previous.data, ...piece.data]),
            kind: previous.kind,
            bank: previous.bank,
          );
          continue;
        }
      }
      compacted.add(piece);
    }
  }
  return List.unmodifiable(compacted);
}

class SnapshotRegisterPatcher {
  const SnapshotRegisterPatcher();

  static int encodeRefreshRegister(int savedR) {
    final highBit = savedR & 0x80;
    final lowBits =
        ((savedR & 0x7f) -
            SnapshotReceiverManifest.registerFetchesAfterRRestore) &
        0x7f;
    return highBit | lowBits;
  }

  static int restoredRefreshRegister(int encodedR) {
    final highBit = encodedR & 0x80;
    final lowBits =
        ((encodedR & 0x7f) +
            SnapshotReceiverManifest.registerFetchesAfterRRestore) &
        0x7f;
    return highBit | lowBits;
  }

  Uint8List patch(Uint8List template, SnapshotRegisters registers) {
    if (template.length != SnapshotReceiverManifest.registerLength) {
      throw SnapshotException(
        SnapshotErrorCode.invalidAsset,
        'Register restoration blob has ${template.length} bytes; expected '
        '${SnapshotReceiverManifest.registerLength}',
      );
    }
    if (registers.interruptMode < 0 || registers.interruptMode > 2) {
      throw SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Unsupported interrupt mode ${registers.interruptMode}',
      );
    }
    if (registers.border < 0 || registers.border > 7) {
      throw SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Invalid border value ${registers.border}',
      );
    }

    final result = Uint8List.fromList(template);
    final offsets = SnapshotReceiverManifest.registerOffsets;
    void byte(String name, int value) => result[offsets[name]!] = value & 0xff;
    void word(String name, int value) {
      final offset = offsets[name]!;
      result[offset] = value & 0xff;
      result[offset + 1] = (value >> 8) & 0xff;
    }

    word('af', registers.af);
    word('afAlt', registers.afAlt);
    byte('border', registers.border);
    word('bcAlt', registers.bcAlt);
    word('deAlt', registers.deAlt);
    word('hlAlt', registers.hlAlt);
    word('bc', registers.bc);
    word('de', registers.de);
    word('hl', registers.hl);
    word('ix', registers.ix);
    word('iy', registers.iy);
    byte('r', encodeRefreshRegister(registers.r));
    byte('i', registers.i);
    word('sp', registers.sp);
    word(
      'interruptMode',
      const [0x46ed, 0x56ed, 0x5eed][registers.interruptMode],
    );
    byte('interruptEnable', registers.interruptsEnabled ? 0xfb : 0xf3);
    word('pc', registers.pc);
    return result;
  }
}

class SnapshotReceiverPatcher {
  const SnapshotReceiverPatcher();

  Uint8List patch(
    Uint8List receiverTap,
    SnapshotReceiverLayout layout,
    int loaderStart, {
    required SnapshotTurboProfile turboProfile,
  }) {
    if (receiverTap.length != layout.length) {
      throw SnapshotException(
        SnapshotErrorCode.invalidAsset,
        'Receiver length changed before patching',
      );
    }
    final target = loaderStart + SnapshotReceiverLayout.stackSize;
    final result = Uint8List.fromList(receiverTap);

    void byteAtAddress(int address, int value) {
      final offset = layout.rawTapOffsetForAddress(address);
      if (offset < 0 || offset >= result.length) {
        throw SnapshotException(
          SnapshotErrorCode.invalidAsset,
          'Receiver patch address 0x${address.toRadixString(16)} is outside asset',
        );
      }
      result[offset] = value & 0xff;
    }

    void wordAtAddress(int address, int value) {
      byteAtAddress(address, value);
      byteAtAddress(address + 1, value >> 8);
    }

    wordAtAddress(layout.copyStackPointerAddress, target);
    if (target > layout.controlCodeStart) {
      wordAtAddress(
        layout.copyDestinationAddress,
        target + layout.controlCodeLength - 1,
      );
      wordAtAddress(
        layout.copySourceAddress,
        layout.controlCodeStart + layout.controlCodeLength - 1,
      );
      wordAtAddress(layout.copyInstructionAddress, 0xb8ed);
    } else {
      wordAtAddress(layout.copyDestinationAddress, target);
      wordAtAddress(layout.copySourceAddress, layout.controlCodeStart);
      wordAtAddress(layout.copyInstructionAddress, 0xb0ed);
    }
    wordAtAddress(layout.copyJumpAddress, target);
    byteAtAddress(layout.leaderMaxFirstAddress, turboProfile.receiverLeaderMax);
    byteAtAddress(
      layout.leaderMinCompareFirstAddress,
      turboProfile.receiverLeaderMinCompare,
    );
    byteAtAddress(
      layout.leaderMaxSecondAddress,
      turboProfile.receiverLeaderMax,
    );
    byteAtAddress(
      layout.syncMinCompareAddress,
      turboProfile.receiverSyncMinCompare,
    );
    byteAtAddress(
      layout.leaderMinCompareSecondAddress,
      turboProfile.receiverLeaderMinCompare,
    );
    byteAtAddress(layout.bitLoopMaxAddress, SnapshotTiming.bitLoopMax);
    byteAtAddress(
      layout.miniSyncMaxAddress,
      SnapshotTiming.receiverMiniSyncMax,
    );
    byteAtAddress(layout.bitOneThresholdAddress, turboProfile.bitOneThreshold);
    byteAtAddress(layout.ioInitAddress, SnapshotTiming.ioInitial);
    byteAtAddress(layout.ioXorAddress, SnapshotTiming.ioXor);
    _recalculateCodeBlockChecksum(result);
    return result;
  }

  void _recalculateCodeBlockChecksum(Uint8List tap) {
    var offset = 0;
    var blockIndex = 0;
    while (offset < tap.length) {
      if (offset + 2 > tap.length) {
        throw const SnapshotException(
          SnapshotErrorCode.invalidAsset,
          'Truncated TAP block length',
        );
      }
      final length = tap[offset] | (tap[offset + 1] << 8);
      final start = offset + 2;
      final end = start + length;
      if (length < 2 || end > tap.length) {
        throw const SnapshotException(
          SnapshotErrorCode.invalidAsset,
          'Invalid TAP block in receiver asset',
        );
      }
      if (blockIndex == 1) {
        var checksum = 0;
        for (var index = start; index < end - 1; index++) {
          checksum ^= tap[index];
        }
        tap[end - 1] = checksum;
        return;
      }
      offset = end;
      blockIndex++;
    }
    throw const SnapshotException(
      SnapshotErrorCode.invalidAsset,
      'Receiver TAP has no code block',
    );
  }
}

class SnapshotRelocationExclusion {
  const SnapshotRelocationExclusion({
    required this.name,
    required this.start,
    required this.end,
  }) : assert(start >= 0),
       assert(end >= start),
       assert(end <= SnapshotMemoryRange.addressSpaceSize);

  final String name;
  final int start;
  final int end;

  bool overlaps(int otherStart, int otherEnd) =>
      end > otherStart && start < otherEnd;
}

class SnapshotRestorePlan {
  SnapshotRestorePlan({
    required this.snapshot,
    required this.turboProfile,
    required this.layout,
    required this.loaderStart,
    required this.registerCodeStart,
    required this.stagingAddress,
    required this.relocatedWorkingLength,
    required Uint8List receiverTap,
    required Uint8List expectedFixedRam,
    required List<SnapshotMemoryRange> blocks,
    required this.usedScreenFallback,
  }) : receiverTap = Uint8List.fromList(receiverTap),
       expectedFixedRam = Uint8List.fromList(expectedFixedRam),
       blocks = List.unmodifiable(blocks);

  final SpectrumSnapshot snapshot;
  final SnapshotTurboProfile turboProfile;
  final SnapshotReceiverLayout layout;
  final int loaderStart;
  final int registerCodeStart;
  final int stagingAddress;
  final int relocatedWorkingLength;
  final Uint8List receiverTap;
  final Uint8List expectedFixedRam;
  final List<SnapshotMemoryRange> blocks;
  final bool usedScreenFallback;

  int get finalOut7ffd => snapshot.lastOut7ffd ?? -1;

  void validate() {
    if (blocks.isEmpty) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Restore plan has no blocks',
      );
    }
    final executions = blocks
        .where((block) => block.executionAddress != null)
        .toList();
    if (executions.length != 1 ||
        !identical(executions.single, blocks.last) ||
        executions.single.executionAddress != registerCodeStart) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Only the final block may transfer execution to the register blob',
      );
    }
    final last = blocks.last;
    if (last.kind != SnapshotRangeKind.finalOverwrite ||
        last.start != layout.upperStart ||
        last.data.length != layout.upperLength) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Upper receiver overwrite must be the complete final block',
      );
    }
    if (blocks.first.kind != SnapshotRangeKind.screen ||
        blocks.first.start != 0x4000 ||
        blocks.first.data.length != SnapshotRestorePlanner.screenLength) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'The display must be restored by the first block',
      );
    }

    final fixedCounts = Uint8List(0xc000);
    final fixedValues = Uint8List(0xc000);
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      if (block.isEmpty) {
        throw const SnapshotException(
          SnapshotErrorCode.invalidRestorePlan,
          'Restore plan contains an empty block',
        );
      }
      if (block.bank == null) {
        for (var offset = 0; offset < block.data.length; offset++) {
          final address = block.start + offset;
          if (address < 0x4000 || address > 0xffff) {
            throw const SnapshotException(
              SnapshotErrorCode.invalidRestorePlan,
              'Fixed restore block lies outside RAM',
            );
          }
          final index = address - 0x4000;
          fixedCounts[index]++;
          fixedValues[index] = block.data[offset];
        }
      } else {
        if (block.start != 0xc000 ||
            block.data.length != SpectrumSnapshot.bankSize) {
          throw const SnapshotException(
            SnapshotErrorCode.invalidRestorePlan,
            'Banked restore blocks must cover exactly 0xc000-0xffff',
          );
        }
      }

      if (blockIndex > 0 &&
          blockIndex < blocks.length - 1 &&
          block.bank == null &&
          block.overlaps(loaderStart, loaderStart + relocatedWorkingLength)) {
        throw const SnapshotException(
          SnapshotErrorCode.invalidRestorePlan,
          'A later block overwrites the live relocated receiver',
        );
      }
    }

    for (var index = 0; index < fixedCounts.length; index++) {
      final address = 0x4000 + index;
      final isWorking =
          address >= loaderStart &&
          address < loaderStart + relocatedWorkingLength;
      final expectedCount = isWorking && !usedScreenFallback ? 0 : 1;
      if (fixedCounts[index] != expectedCount) {
        throw SnapshotException(
          SnapshotErrorCode.invalidRestorePlan,
          'Fixed RAM address 0x${address.toRadixString(16)} is written '
          '${fixedCounts[index]} times; expected $expectedCount',
        );
      }
      if (expectedCount == 1 && fixedValues[index] != expectedFixedRam[index]) {
        throw SnapshotException(
          SnapshotErrorCode.invalidRestorePlan,
          'Fixed RAM byte mismatch at 0x${address.toRadixString(16)}',
        );
      }
    }

    final banked = {
      for (final block in blocks)
        if (block.bank != null) block.bank!,
    };
    final expectedBanks =
        snapshot.machine == SpectrumSnapshotMachine.spectrum128k
        ? const {1, 3, 4, 6, 7}
        : const <int>{};
    if (banked.length != expectedBanks.length ||
        banked.difference(expectedBanks).isNotEmpty ||
        expectedBanks.difference(banked).isNotEmpty) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Restore plan does not contain each switchable bank exactly once',
      );
    }
    for (final block in blocks.where((block) => block.bank != null)) {
      final expected = snapshot.bank(block.bank!);
      for (var index = 0; index < expected.length; index++) {
        if (block.data[index] != expected[index]) {
          throw SnapshotException(
            SnapshotErrorCode.invalidRestorePlan,
            'RAM bank ${block.bank} differs at offset $index',
          );
        }
      }
    }
  }
}

class SnapshotRestorePlanner {
  const SnapshotRestorePlanner({
    this.registerPatcher = const SnapshotRegisterPatcher(),
    this.receiverPatcher = const SnapshotReceiverPatcher(),
  });

  static const int screenLength = 6912;
  static const int screenStart = 0x4000;
  static const int afterScreen = screenStart + screenLength;
  static const int fallbackLoaderStart = 0x5000;

  final SnapshotRegisterPatcher registerPatcher;
  final SnapshotReceiverPatcher receiverPatcher;

  SnapshotRestorePlan createPlan(
    SpectrumSnapshot snapshot,
    SnapshotAssetBundle assets, {
    required SnapshotTurboProfile turboProfile,
  }) {
    assets.verify();
    final layout = SnapshotReceiverManifest.layoutFor(snapshot.machine);
    final workingLength =
        SnapshotReceiverLayout.stackSize +
        layout.controlCodeLength +
        layout.upperLength;
    final requiredLength =
        workingLength + SnapshotReceiverManifest.registerLength;
    final fixedRam = _initialFixedRam(snapshot);
    final relocationExclusions = _criticalRelocationExclusions(snapshot);
    final loaderStart = findRelocation(
      fixedRam,
      layout,
      requiredLength: requiredLength,
      exclusions: relocationExclusions,
    );
    final usedScreenFallback = loaderStart == fallbackLoaderStart;
    final registerCodeStart = loaderStart + workingLength;
    if (registerCodeStart + SnapshotReceiverManifest.registerLength >
        layout.upperStart) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Register restoration blob would overlap the upper receiver',
      );
    }

    final patchedRegisters = registerPatcher.patch(
      assets.registerBlob,
      snapshot.registers,
    );
    fixedRam.setRange(
      registerCodeStart - screenStart,
      registerCodeStart - screenStart + patchedRegisters.length,
      patchedRegisters,
    );
    final patchedReceiver = receiverPatcher.patch(
      assets.receiverFor(snapshot.machine),
      layout,
      loaderStart,
      turboProfile: turboProfile,
    );

    var fixedRanges = <SnapshotMemoryRange>[
      SnapshotMemoryRange(
        name: 'Screen',
        start: screenStart,
        data: Uint8List.fromList(fixedRam.sublist(0, screenLength)),
        kind: SnapshotRangeKind.screen,
      ),
      SnapshotMemoryRange(
        name: 'Fixed RAM',
        start: afterScreen,
        data: Uint8List.fromList(fixedRam.sublist(screenLength)),
        kind: SnapshotRangeKind.fixedRam,
      ),
    ];

    if (!usedScreenFallback) {
      fixedRanges = _removeRegion(
        fixedRanges,
        loaderStart,
        loaderStart + workingLength,
      );
    }
    SnapshotMemoryRange? finalOverwrite;
    final withoutUpper = <SnapshotMemoryRange>[];
    for (final range in fixedRanges) {
      if (!range.overlaps(
        layout.upperStart,
        layout.upperStart + layout.upperLength,
      )) {
        withoutUpper.add(range);
        continue;
      }
      for (final piece in range.splitAround(
        layout.upperStart,
        layout.upperStart + layout.upperLength,
      )) {
        if (piece.start == layout.upperStart &&
            piece.end == layout.upperStart + layout.upperLength) {
          if (finalOverwrite != null) {
            throw const SnapshotException(
              SnapshotErrorCode.invalidRestorePlan,
              'Upper receiver region appears more than once',
            );
          }
          finalOverwrite = piece.copyWith(
            name: 'Final receiver overwrite',
            kind: SnapshotRangeKind.finalOverwrite,
            executionAddress: registerCodeStart,
          );
        } else {
          withoutUpper.add(piece);
        }
      }
    }
    if (finalOverwrite == null) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Snapshot does not cover the upper receiver region',
      );
    }

    withoutUpper.sort((left, right) => left.start.compareTo(right.start));
    final blocks = <SnapshotMemoryRange>[...withoutUpper];
    if (snapshot.machine == SpectrumSnapshotMachine.spectrum128k) {
      for (final bank in const [1, 3, 4, 6, 7]) {
        blocks.add(
          SnapshotMemoryRange(
            name: 'RAM bank $bank',
            start: 0xc000,
            data: snapshot.bank(bank),
            kind: SnapshotRangeKind.bankedRam,
            bank: bank,
          ),
        );
      }
    }
    blocks.add(finalOverwrite);

    final plan = SnapshotRestorePlan(
      snapshot: snapshot,
      turboProfile: turboProfile,
      layout: layout,
      loaderStart: loaderStart,
      registerCodeStart: registerCodeStart,
      stagingAddress:
          loaderStart +
          SnapshotReceiverLayout.stackSize +
          layout.controlCodeLength,
      relocatedWorkingLength: workingLength,
      receiverTap: patchedReceiver,
      expectedFixedRam: fixedRam,
      blocks: blocks,
      usedScreenFallback: usedScreenFallback,
    );
    plan.validate();
    return plan;
  }

  int findRelocation(
    Uint8List fixedRam,
    SnapshotReceiverLayout layout, {
    required int requiredLength,
    Iterable<SnapshotRelocationExclusion> exclusions = const [],
  }) {
    if (fixedRam.length != 3 * SpectrumSnapshot.bankSize) {
      throw const SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Relocation search requires the fixed 48K RAM view',
      );
    }
    final searchStart = afterScreen;
    final searchEnd = layout.upperStart;
    final activeReceiverStart = layout.totalStart;
    final activeReceiverEnd = layout.totalStart + layout.totalLength;
    final exclusionList = exclusions.toList(growable: false);
    var runStart = -1;
    for (var address = searchStart; address < searchEnd; address++) {
      final candidateEnd = address + 1;
      final inActiveReceiver =
          address >= activeReceiverStart && address < activeReceiverEnd;
      final isExcluded = exclusionList.any(
        (range) => address >= range.start && address < range.end,
      );
      final byte = fixedRam[address - screenStart];
      if (byte != 0 || inActiveReceiver || isExcluded) {
        runStart = -1;
        continue;
      }
      runStart = runStart < 0 ? address : runStart;
      if (candidateEnd - runStart >= requiredLength) {
        final end = runStart + requiredLength;
        if (end <= searchEnd &&
            !_overlaps(runStart, end, activeReceiverStart, activeReceiverEnd)) {
          return runStart;
        }
        runStart = -1;
      }
    }
    final fallbackEnd = fallbackLoaderStart + requiredLength;
    SnapshotRelocationExclusion? fallbackConflict;
    for (final range in exclusionList) {
      if (range.overlaps(fallbackLoaderStart, fallbackEnd)) {
        fallbackConflict = range;
        break;
      }
    }
    if (fallbackConflict != null) {
      throw SnapshotException(
        SnapshotErrorCode.invalidRestorePlan,
        'Screen fallback would overwrite the saved '
        '${fallbackConflict.name} range',
      );
    }
    return fallbackLoaderStart;
  }

  List<SnapshotRelocationExclusion> _criticalRelocationExclusions(
    SpectrumSnapshot snapshot,
  ) {
    final registers = snapshot.registers;
    final exclusions = <SnapshotRelocationExclusion>[];

    void add(String name, int start, int length) {
      if (start >= SnapshotMemoryRange.addressSpaceSize ||
          start + length <= screenStart) {
        return;
      }
      exclusions.add(
        SnapshotRelocationExclusion(
          name: name,
          start: start < screenStart ? screenStart : start,
          end: start + length > SnapshotMemoryRange.addressSpaceSize
              ? SnapshotMemoryRange.addressSpaceSize
              : start + length,
        ),
      );
    }

    // Preserve the longest possible instruction beginning at the resume PC,
    // the next stack word, and the complete IM 2 vector page. Other zero RAM
    // remains eligible because the receiver necessarily needs a scratch area.
    add('PC instruction', registers.pc, 4);
    add('SP stack word', registers.sp, 2);
    if (registers.interruptMode == 2) {
      add('IM 2 vector table', registers.i << 8, 0x101);
    }
    return List.unmodifiable(exclusions);
  }

  Uint8List _initialFixedRam(SpectrumSnapshot snapshot) {
    final result = Uint8List(3 * SpectrumSnapshot.bankSize);
    result.setRange(0, SpectrumSnapshot.bankSize, snapshot.bank(5));
    result.setRange(
      SpectrumSnapshot.bankSize,
      2 * SpectrumSnapshot.bankSize,
      snapshot.bank(2),
    );
    result.setRange(
      2 * SpectrumSnapshot.bankSize,
      3 * SpectrumSnapshot.bankSize,
      snapshot.bank(0),
    );
    return result;
  }

  List<SnapshotMemoryRange> _removeRegion(
    Iterable<SnapshotMemoryRange> ranges,
    int start,
    int end,
  ) {
    final result = <SnapshotMemoryRange>[];
    for (final range in ranges) {
      if (!range.overlaps(start, end)) {
        result.add(range);
        continue;
      }
      for (final piece in range.splitAround(start, end)) {
        if (piece.end <= start || piece.start >= end) result.add(piece);
      }
    }
    return result;
  }

  static bool _overlaps(int start, int end, int otherStart, int otherEnd) =>
      end > otherStart && start < otherEnd;
}
