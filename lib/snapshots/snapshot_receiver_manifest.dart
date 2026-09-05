import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'snapshot_error.dart';
import 'snapshot_models.dart';

class SnapshotReceiverLayout {
  const SnapshotReceiverLayout({
    required this.assetPath,
    required this.length,
    required this.sha256,
    required this.totalStart,
    required this.totalLength,
    required this.clearAddress,
    required this.controlCodeStart,
    required this.controlCodeLength,
    required this.upperStartOffset,
    required this.upperStart,
    required this.upperLength,
    required this.copyStackPointerAddress,
    required this.copyDestinationAddress,
    required this.copySourceAddress,
    required this.copyInstructionAddress,
    required this.copyJumpAddress,
    required this.leaderMaxFirstAddress,
    required this.leaderMinCompareFirstAddress,
    required this.leaderMaxSecondAddress,
    required this.syncMinCompareAddress,
    required this.leaderMinCompareSecondAddress,
    required this.bitLoopMaxAddress,
    required this.miniSyncMaxAddress,
    required this.bitOneThresholdAddress,
    required this.ioInitAddress,
    required this.ioXorAddress,
  });

  final String assetPath;
  final int length;
  final String sha256;
  final int totalStart;
  final int totalLength;
  final int clearAddress;
  final int controlCodeStart;
  final int controlCodeLength;
  final int upperStartOffset;
  final int upperStart;
  final int upperLength;
  final int copyStackPointerAddress;
  final int copyDestinationAddress;
  final int copySourceAddress;
  final int copyInstructionAddress;
  final int copyJumpAddress;
  final int leaderMaxFirstAddress;
  final int leaderMinCompareFirstAddress;
  final int leaderMaxSecondAddress;
  final int syncMinCompareAddress;
  final int leaderMinCompareSecondAddress;
  final int bitLoopMaxAddress;
  final int miniSyncMaxAddress;
  final int bitOneThresholdAddress;
  final int ioInitAddress;
  final int ioXorAddress;

  static const int stackSize = 10;
  static const int tapHeaderBlockLength = 19;
  static const int rawTapCodeBlockOffset = 2 + tapHeaderBlockLength + 2;

  int codeBlockOffsetForAddress(int address) {
    var adjusted = address;
    if (adjusted >= upperStart) {
      adjusted = adjusted - upperStart + upperStartOffset;
    }
    return 1 + adjusted - totalStart;
  }

  int rawTapOffsetForAddress(int address) =>
      rawTapCodeBlockOffset + codeBlockOffsetForAddress(address);
}

class SnapshotReceiverManifest {
  const SnapshotReceiverManifest._();

  static const String protocolVersion =
      'zqloader-a6fdb6a-zxtp-v3-header-check-failsafe';
  static const String registerAssetPath = 'assets/snapshots/snapshotregs.bin';
  static const int turboHeaderLength = 18;
  static const int registerLength = 59;
  // M1 fetches performed after the register blob executes LD R,A and before
  // control reaches the restored PC. The host pre-compensates the low 7 bits.
  static const int registerFetchesAfterRRestore = 9;
  static const String registerSha256 =
      'a31fde91bc259ac4fdd3d442627f8495b98a9bae66644f1eb7b1414a181ad96f';

  static const SnapshotReceiverLayout receiver48 = SnapshotReceiverLayout(
    assetPath: 'assets/snapshots/zqloader48.tap',
    length: 463,
    sha256: '80d5fee750bad222526468bf6df3f54a36182fb9b1335aced70ec849a439ccf5',
    totalStart: 0x5ccb,
    totalLength: 0x01b6,
    clearAddress: 0x5f81,
    controlCodeStart: 0x5cfa,
    controlCodeLength: 0x00be,
    upperStartOffset: 0x5db8,
    upperStart: 0xff38,
    upperLength: 0x00c8,
    copyStackPointerAddress: 0xff54,
    copyDestinationAddress: 0xff57,
    copySourceAddress: 0xff5a,
    copyInstructionAddress: 0xff5f,
    copyJumpAddress: 0xff62,
    leaderMaxFirstAddress: 0xff72,
    leaderMinCompareFirstAddress: 0xff7a,
    leaderMaxSecondAddress: 0xff81,
    syncMinCompareAddress: 0xff89,
    leaderMinCompareSecondAddress: 0xff8d,
    bitLoopMaxAddress: 0xffb0,
    miniSyncMaxAddress: 0xffb2,
    bitOneThresholdAddress: 0xffca,
    ioInitAddress: 0x5d04,
    ioXorAddress: 0x5d06,
  );

  static const SnapshotReceiverLayout receiver128 = SnapshotReceiverLayout(
    assetPath: 'assets/snapshots/zqloader128.tap',
    length: 476,
    sha256: '32a2bbfc10e8c3139736f88d72b5031dde3ba7205768fd9c6e71ba8e7dd57f34',
    totalStart: 0x5ccb,
    totalLength: 0x01c3,
    clearAddress: 0x5f8e,
    controlCodeStart: 0x5cfa,
    controlCodeLength: 0x00cb,
    upperStartOffset: 0x5dc5,
    upperStart: 0xbf38,
    upperLength: 0x00c8,
    copyStackPointerAddress: 0xbf54,
    copyDestinationAddress: 0xbf57,
    copySourceAddress: 0xbf5a,
    copyInstructionAddress: 0xbf5f,
    copyJumpAddress: 0xbf62,
    leaderMaxFirstAddress: 0xbf72,
    leaderMinCompareFirstAddress: 0xbf7a,
    leaderMaxSecondAddress: 0xbf81,
    syncMinCompareAddress: 0xbf89,
    leaderMinCompareSecondAddress: 0xbf8d,
    bitLoopMaxAddress: 0xbfb0,
    miniSyncMaxAddress: 0xbfb2,
    bitOneThresholdAddress: 0xbfca,
    ioInitAddress: 0x5d04,
    ioXorAddress: 0x5d06,
  );

  static const Map<String, int> registerOffsets = {
    'af': 0x01,
    'afAlt': 0x05,
    'border': 0x09,
    'bcAlt': 0x0d,
    'deAlt': 0x10,
    'hlAlt': 0x13,
    'bc': 0x19,
    'de': 0x1c,
    'hl': 0x1f,
    'ix': 0x23,
    'iy': 0x27,
    'r': 0x2a,
    'i': 0x2e,
    'sp': 0x33,
    'interruptMode': 0x35,
    'interruptEnable': 0x37,
    'pc': 0x39,
  };

  static SnapshotReceiverLayout layoutFor(SpectrumSnapshotMachine machine) =>
      machine == SpectrumSnapshotMachine.spectrum48k ? receiver48 : receiver128;

  static void verifyAsset(
    Uint8List bytes, {
    required int expectedLength,
    required String expectedSha256,
    required String label,
  }) {
    if (bytes.length != expectedLength) {
      throw SnapshotException(
        SnapshotErrorCode.invalidAsset,
        '$label has ${bytes.length} bytes; expected $expectedLength',
      );
    }
    final actual = sha256.convert(bytes).toString();
    if (actual != expectedSha256) {
      throw SnapshotException(
        SnapshotErrorCode.invalidAsset,
        '$label checksum $actual does not match $expectedSha256',
      );
    }
  }
}

class SnapshotAssetBundle {
  SnapshotAssetBundle({
    required Uint8List receiver48Tap,
    required Uint8List receiver128Tap,
    required Uint8List registerBlob,
  }) : receiver48Tap = Uint8List.fromList(receiver48Tap),
       receiver128Tap = Uint8List.fromList(receiver128Tap),
       registerBlob = Uint8List.fromList(registerBlob);

  final Uint8List receiver48Tap;
  final Uint8List receiver128Tap;
  final Uint8List registerBlob;

  void verify() {
    SnapshotReceiverManifest.verifyAsset(
      receiver48Tap,
      expectedLength: SnapshotReceiverManifest.receiver48.length,
      expectedSha256: SnapshotReceiverManifest.receiver48.sha256,
      label: '48K receiver',
    );
    SnapshotReceiverManifest.verifyAsset(
      receiver128Tap,
      expectedLength: SnapshotReceiverManifest.receiver128.length,
      expectedSha256: SnapshotReceiverManifest.receiver128.sha256,
      label: '128K receiver',
    );
    SnapshotReceiverManifest.verifyAsset(
      registerBlob,
      expectedLength: SnapshotReceiverManifest.registerLength,
      expectedSha256: SnapshotReceiverManifest.registerSha256,
      label: 'register restoration blob',
    );
  }

  Uint8List receiverFor(SpectrumSnapshotMachine machine) => Uint8List.fromList(
    machine == SpectrumSnapshotMachine.spectrum48k
        ? receiver48Tap
        : receiver128Tap,
  );
}
