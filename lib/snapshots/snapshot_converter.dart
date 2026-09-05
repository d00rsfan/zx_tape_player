import 'dart:typed_data';

import 'snapshot_decoder.dart';
import 'snapshot_models.dart';
import 'snapshot_receiver_manifest.dart';
import 'snapshot_renderer.dart';
import 'snapshot_restore_planner.dart';
import 'snapshot_timing.dart';
import 'snapshot_turbo_codec.dart';

class SnapshotConversionResult {
  SnapshotConversionResult({
    required this.snapshot,
    required this.turboProfile,
    required this.invertPolarity,
    required this.sampleRate,
    required this.restorePlan,
    required List<SnapshotTurboBlock> turboBlocks,
    required this.wav,
  }) : turboBlocks = List.unmodifiable(turboBlocks);

  final SpectrumSnapshot snapshot;
  final SnapshotTurboProfile turboProfile;
  final bool invertPolarity;
  final SnapshotAudioSampleRate sampleRate;
  final SnapshotRestorePlan restorePlan;
  final List<SnapshotTurboBlock> turboBlocks;
  final SnapshotWavResult wav;

  List<SnapshotWarning> get warnings => snapshot.warnings;
}

class SnapshotConverter {
  const SnapshotConverter({
    this.decoder = const SnapshotDecoder(),
    this.planner = const SnapshotRestorePlanner(),
    this.turboEncoder = const SnapshotTurboStreamEncoder(),
    this.renderer = const SnapshotWavRenderer(),
  });

  final SnapshotDecoder decoder;
  final SnapshotRestorePlanner planner;
  final SnapshotTurboStreamEncoder turboEncoder;
  final SnapshotWavRenderer renderer;

  SnapshotConversionResult convert({
    required Uint8List snapshotBytes,
    required String fileName,
    required SnapshotAssetBundle assets,
    required SnapshotTurboProfile turboProfile,
    required bool invertPolarity,
    SnapshotAudioSampleRate sampleRate = SnapshotTiming.defaultSampleRate,
    void Function(int progress)? onProgress,
  }) {
    final snapshot = decoder.decode(snapshotBytes, fileName);
    final restorePlan = planner.createPlan(
      snapshot,
      assets,
      turboProfile: turboProfile,
    );
    final turboBlocks = turboEncoder.encode(restorePlan);
    final wav = renderer.render(
      restorePlan.receiverTap,
      turboBlocks,
      turboProfile: turboProfile,
      invertPolarity: invertPolarity,
      sampleRate: sampleRate,
      onProgress: onProgress,
    );
    return SnapshotConversionResult(
      snapshot: snapshot,
      turboProfile: turboProfile,
      invertPolarity: invertPolarity,
      sampleRate: sampleRate,
      restorePlan: restorePlan,
      turboBlocks: turboBlocks,
      wav: wav,
    );
  }
}
