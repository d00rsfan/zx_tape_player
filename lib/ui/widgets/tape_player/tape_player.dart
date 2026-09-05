import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/models/software_model.dart';
import 'package:zx_tape_player/services/backend_service.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/silence_control_service.dart';
import 'package:zx_tape_player/services/snapshot_asset_service.dart';
import 'package:zx_tape_player/services/snapshot_cache_service.dart';
import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/services/wake_lock_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/media_selection.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/models/position_data.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/models/progress_model.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/models/tape_player_data.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/block_browser.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/playback_policy.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/rate_control_sheet.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/seek_bar.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/snapshot_messages.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/snapshot_profile_session.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/transport_controls.dart';
import 'package:zx_tape_player/utils/bar_helper.dart';
import 'package:zx_tape_player/utils/definitions.dart';
import 'package:zx_tape_player/utils/extensions.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class TapePlayerController {
  Future<String> Function()? _prepareTapeImageExport;
  Future<String?> Function()? _prepareWavExport;
  Future<String> Function()? _prepareOriginalArchiveExport;
  bool Function()? _isWavReady;
  bool Function()? _isCurrentFileZip;
  bool Function()? _isSnapshot;

  Future<String> prepareTapeImageExport() => _prepareTapeImageExport!();
  Future<String?> prepareWavExport() => _prepareWavExport!();
  Future<String> prepareOriginalArchiveExport() =>
      _prepareOriginalArchiveExport!();
  bool get isWavReady => _isWavReady?.call() ?? false;
  bool get isCurrentFileZip => _isCurrentFileZip?.call() ?? false;
  bool get isSnapshot => _isSnapshot?.call() ?? false;
}

class TapePlayer extends StatefulWidget {
  final SoftwareModel software;
  final TapePlayerController? controller;

  const TapePlayer({super.key, required this.software, this.controller});

  @override
  State<TapePlayer> createState() => _TapePlayerState();
}

// Carousel item text metrics.
const _carouselNameFontSize = 12.0;
const _carouselSourceFontSize = 8.0;

// Pessimistic per-line heights used by `_calculateCarouselHeight`. These
// overestimate iOS system-font line heights (San Francisco at 12pt renders at
// roughly 16-18px) so the precomputed carousel height always grows enough to
// fit the rendered text without an overflow assertion. The actual `Text`
// widgets render with natural font metrics — we don't try to lock them, we
// just ensure the container is at least as tall as a generous upper bound.
const _carouselNameLinePx = 24.0; // 12 × 2.0
const _carouselSourceLinePx = 18.0; // 8 × ~2.25

const TextStyle _carouselNameStyle = TextStyle(
  color: Colors.white,
  fontSize: _carouselNameFontSize,
);
const TextStyle _carouselSourceStyle = TextStyle(
  color: Colors.white54,
  fontSize: _carouselSourceFontSize,
);

class _TapePlayerState extends State<TapePlayer> {
  late _TapePlayerBloc _bloc;

  // Drives the download-in-progress indicator shown over the filename strip.
  // Held visible for at least [_minDownloadIndicator] so a fast save (<200ms
  // on Wi-Fi) doesn't reduce it to an unnoticeable flicker.
  bool _downloading = false;
  static const _minDownloadIndicator = Duration(milliseconds: 500);

  @override
  void initState() {
    _bloc = _TapePlayerBloc(widget.software, controller: widget.controller);
    super.initState();
  }

  @override
  void dispose() {
    _bloc.dispose();
    super.dispose();
  }

  void _showSliderBottomSheet({
    required BuildContext context,
    required String title,
    required int divisions,
    required double min,
    required double max,
    String valueSuffix = '',
    int decimals = 1,
    List<double>? presets,
    required Stream<double> stream,
    required ValueChanged<double> onChanged,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaybackSpeedSheet(
        title: title,
        divisions: divisions,
        min: min,
        max: max,
        valueSuffix: valueSuffix,
        decimals: decimals,
        presets: presets,
        stream: stream,
        onChanged: onChanged,
      ),
    );
  }

  void _showSnapshotProfileBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SnapshotTurboProfileSheet(
        title: tr('snapshot_turbo_profile_title'),
        explanation: tr('snapshot_turbo_profile_explanation'),
        invertPolarityLabel: tr('snapshot_invert_polarity'),
        activeProfile: _bloc.snapshotTurboProfile,
        invertPolarity: _bloc.snapshotInvertPolarity,
        sampleRateLabel: tr('snapshot_sample_rate'),
        sampleRate: _bloc.snapshotSampleRate,
        onSelected: (profile) {
          Navigator.pop(sheetContext);
          unawaited(
            _bloc.selectSnapshotSignalSettings(
              profile: profile,
              invertPolarity: _bloc.snapshotInvertPolarity,
              sampleRate: _bloc.snapshotSampleRate,
            ),
          );
        },
        onPolarityChanged: (invertPolarity) {
          Navigator.pop(sheetContext);
          unawaited(
            _bloc.selectSnapshotSignalSettings(
              profile: _bloc.snapshotTurboProfile,
              invertPolarity: invertPolarity,
              sampleRate: _bloc.snapshotSampleRate,
            ),
          );
        },
        onSampleRateChanged: (sampleRate) {
          Navigator.pop(sheetContext);
          unawaited(
            _bloc.selectSnapshotSignalSettings(
              profile: _bloc.snapshotTurboProfile,
              invertPolarity: _bloc.snapshotInvertPolarity,
              sampleRate: sampleRate,
            ),
          );
        },
      ),
    );
  }

  /// Computes a carousel height that fits the largest item without overflow.
  /// Floor is the original 80px; ceiling is ~250% of that (200px). If a file
  /// genuinely needs more, we'd rather see an overflow assertion than silently
  /// shrink the text — that's an indicator to revisit the layout.
  ///
  /// Strategy: count rendered lines accurately with TextPainter, then
  /// multiply by an overestimating per-line constant. This tolerates iOS
  /// system-font metrics that would otherwise undershoot.
  double _calculateCarouselHeight(BuildContext context) {
    const minHeight = 80.0;
    const maxHeight = 200.0;
    const horizontalContainerPadding = 16.0;
    const itemPadding = 12.0;
    const sourceTopPadding = 2.0;
    final mq = MediaQuery.of(context);
    final textScaler = mq.textScaler;
    final textMaxWidth =
        mq.size.width - horizontalContainerPadding * 2 - itemPadding * 2;
    double tallest = 0.0;
    for (final filePath in _bloc.files) {
      final source = _getFileSource(filePath);
      final namePainter = TextPainter(
        text: TextSpan(text: basename(filePath), style: _carouselNameStyle),
        maxLines: 3,
        textDirection: ui.TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: textMaxWidth);
      // Use TextPainter only for the line *count*: computeLineMetrics()
      // accurately tells us how the filename wraps to 1, 2, or 3 lines at
      // the actual screen width. We deliberately discard namePainter.height
      // — empirically on iOS the Text widget renders ~8px taller than what
      // TextPainter reports for the same string, so trusting it caused a
      // RenderFlex overflow. Multiplying the line count by the pessimistic
      // _carouselNameLinePx constant guarantees the budget always exceeds
      // what Text actually paints.
      final nameLines = namePainter.computeLineMetrics().length;
      double h = nameLines * _carouselNameLinePx;
      if (source.isNotEmpty) {
        h += sourceTopPadding + _carouselSourceLinePx;
      }
      h += itemPadding * 2;
      if (h > tallest) tallest = h;
    }
    return tallest.clamp(minHeight, maxHeight);
  }

  static String _getFileSource(String filePath) {
    if (filePath.contains('World_of_Spectrum')) return 'archive.org';
    if (filePath.contains('mirror-ftp-nvg')) return 'nvg';
    if (filePath.contains('spectrumcomputing.co.uk')) {
      return 'spectrumcomputing';
    }
    if (filePath.contains('zx_spectrum_tosec')) return 'tosec';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        width: MediaQuery.of(context).size.width,
        color: HexColor('#3B4E63'),
        child: StreamBuilder<PlayerState>(
          stream: _bloc.player.playerStateStream,
          builder: (context, snapshot) {
            var playerState = snapshot.data;
            return StreamBuilder<TapePlayerData>(
              stream: _bloc.tapePlayerStream,
              builder: (context, snapshot) {
                var tapePlayerData = snapshot.data;
                final tapeLoading =
                    tapePlayerData?.state == TapePlayerState.loading;
                final carouselHeight = _calculateCarouselHeight(context);
                return Column(
                  children: [
                    Column(
                      children: [
                        GestureDetector(
                          onLongPress: () async {
                            if (_downloading) return;
                            HapticFeedback.vibrate();
                            setState(() => _downloading = true);
                            final startedAt = DateTime.now();
                            bool saved = false;
                            Object? error;
                            try {
                              saved = await _bloc.downloadSelectedTape();
                            } catch (e) {
                              error = e;
                            }
                            final elapsed = DateTime.now().difference(
                              startedAt,
                            );
                            if (elapsed < _minDownloadIndicator) {
                              await Future.delayed(
                                _minDownloadIndicator - elapsed,
                              );
                            }
                            if (!context.mounted) return;
                            setState(() => _downloading = false);
                            if (error != null) {
                              BarHelper.showSnackBar(
                                message: tr('download_tape_error'),
                                barType: SnackBarType.error,
                                context: context,
                              );
                            } else if (saved) {
                              BarHelper.showSnackBar(
                                message: tr('download_tape_success'),
                                context: context,
                              );
                            } else if (widget.software.isRemote) {
                              // Remote save attempted but didn't land —
                              // e.g. user tapped Deny on the storage
                              // permission prompt on API ≤ 29, or
                              // MediaStore returned null. Without this
                              // branch the long-press would just vibrate
                              // into silence on those devices.
                              BarHelper.showSnackBar(
                                message: tr('download_tape_error'),
                                barType: SnackBarType.error,
                                context: context,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            width: double.infinity,
                            height: carouselHeight,
                            child: Container(
                              decoration: BoxDecoration(
                                color: HexColor('#172434'),
                                borderRadius: BorderRadius.circular(3.5),
                              ),
                              child: Stack(
                                children: [
                                  CarouselSlider(
                                    items: _bloc.files.map((filePath) {
                                      final source = _getFileSource(filePath);
                                      return Container(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                basename(filePath),
                                                style: _carouselNameStyle,
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 3,
                                              ),
                                              if (source.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2.0,
                                                      ),
                                                  child: Text(
                                                    source,
                                                    style: _carouselSourceStyle,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    options: CarouselOptions(
                                      scrollPhysics:
                                          !canScrollMediaCarousel(
                                            position: _bloc.player.position,
                                            optionCount: _bloc.files.length,
                                            loading: tapeLoading,
                                            playbackCompleted:
                                                playerState?.processingState ==
                                                ProcessingState.completed,
                                          )
                                          ? const NeverScrollableScrollPhysics()
                                          : const AlwaysScrollableScrollPhysics(),
                                      autoPlay: false,
                                      enlargeCenterPage: false,
                                      height: carouselHeight,
                                      viewportFraction: 1.0,
                                      initialPage: _bloc.currentFileIndex,
                                      onPageChanged: (index, reason) async {
                                        _bloc.currentFileIndex = index;
                                      },
                                    ),
                                  ),
                                  if (_downloading)
                                    Positioned(
                                      top: 6,
                                      right: 8,
                                      child: Icon(
                                        Icons.download_rounded,
                                        size: 16,
                                        color: HexColor('#4CAF50'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16.0,
                            horizontal: 16.0,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4.0,
                            runSpacing: 4.0,
                            children: _bloc.files.asMap().entries.map((entry) {
                              final index = entry.key;
                              return Container(
                                width: 8.0,
                                height: 8.0,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _bloc.currentFileIndex == index
                                      ? HexColor('#D8DCE0')
                                      : HexColor('#546B7F'),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: StreamBuilder<Duration?>(
                        stream: _bloc.player.durationStream,
                        builder: (context, snapshot) {
                          final duration = snapshot.data ?? Duration.zero;
                          return StreamBuilder<PositionData>(
                            stream:
                                Rx.combineLatest2<
                                  Duration,
                                  Duration,
                                  PositionData
                                >(
                                  _bloc.player.positionStream,
                                  _bloc.player.bufferedPositionStream,
                                  (position, bufferedPosition) =>
                                      PositionData(position, bufferedPosition),
                                ),
                            builder: (context, snapshot) {
                              final positionData =
                                  snapshot.data ??
                                  PositionData(Duration.zero, Duration.zero);
                              var position = positionData.position;
                              if (position > duration) {
                                position = duration;
                              }
                              var bufferedPosition =
                                  positionData.bufferedPosition;
                              if (bufferedPosition > duration) {
                                bufferedPosition = duration;
                              }
                              return SeekBar(
                                duration: duration,
                                position: position,
                                bufferedPosition: bufferedPosition,
                                onChangeEnd: _bloc.policy.canSeekTimeline
                                    ? (newPosition) {
                                        _bloc.player.seek(newPosition);
                                      }
                                    : null,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    _buildCurrentBlockRow(),
                    _buildControlButtons(context, tapePlayerData, playerState),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showBlockBrowser(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => StreamBuilder<Duration>(
          stream: _bloc.player.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            return BlockBrowser(
              blocks: _bloc.blockInfos!,
              currentPosition: position,
              titleKey: _bloc.policy.isSnapshot
                  ? 'snapshot_block_browser'
                  : 'block_browser',
              onBlockTap: _bloc.policy.canNavigateBlocks
                  ? (index) {
                      Navigator.pop(context);
                      _bloc.seekToBlock(index);
                    }
                  : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildCurrentBlockRow() {
    return StreamBuilder<Duration>(
      stream: _bloc.player.positionStream,
      builder: (context, snapshot) {
        final blocks = _bloc.blockInfos;
        if (blocks == null || blocks.isEmpty) {
          return const SizedBox(height: 8.0);
        }
        final index = _bloc.currentBlockIndex ?? 0;
        final block = blocks[index];
        final position = snapshot.data ?? Duration.zero;
        final remaining = block.timeOffset + block.duration - position;
        final clamped = remaining.isNegative ? Duration.zero : remaining;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 32.0,
                child: Text(
                  '${block.index + 1}',
                  maxLines: 2,
                  softWrap: true,
                  style: TextStyle(color: HexColor('#B1B8C1'), fontSize: 11.0),
                ),
              ),
              Icon(
                BlockBrowser.iconForType(block.typeName),
                color: Colors.white,
                size: 16.0,
              ),
              const SizedBox(width: 6.0),
              Expanded(
                child: Text(
                  BlockBrowser.blockLabel(block),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.0,
                    fontWeight: block.isHeader
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6.0),
              Text(
                '-${clamped.toTimeString()}',
                style: TextStyle(color: HexColor('#B1B8C1'), fontSize: 11.0),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButtons(
    BuildContext context,
    TapePlayerData? tapePlayerData,
    PlayerState? playerState,
  ) {
    if (tapePlayerData != null) {
      if (tapePlayerData.state == TapePlayerState.error &&
          _bloc.filePath == tapePlayerData.filePath) {
        BarHelper.showSnackBar(
          message:
              tapePlayerData.mediaKind == TapeMediaKind.snapshot &&
                  tapePlayerData.error != null
              ? snapshotErrorText(tapePlayerData.error!, tr)
              : tapePlayerData.message ?? tr('error_converting_tape_file'),
          barType: SnackBarType.error,
          context: context,
        );
      }
      if (tapePlayerData.warnings.isNotEmpty) {
        BarHelper.showSnackBar(
          message: tapePlayerData.mediaKind == TapeMediaKind.snapshot
              ? tapePlayerData.warnings
                    .map((warning) => snapshotWarningText(warning, tr))
                    .join('\n')
              : tr('tape_corrupted_warning'),
          barType: SnackBarType.warning,
          context: context,
        );
      }
    }

    final processingState = playerState?.processingState;
    final playing = playerState?.playing ?? false;
    final tapeLoading = tapePlayerData?.state == TapePlayerState.loading;
    final hasBlocks = _bloc.blockInfos != null && _bloc.blockInfos!.isNotEmpty;

    return StreamBuilder<double>(
      stream: _bloc.player.speedStream,
      builder: (context, speedSnapshot) {
        final rateControl = _bloc.policy.isSnapshot
            ? TransportRateControl(
                label: _bloc.snapshotTurboProfile.label,
                semanticLabel: tr(
                  'snapshot_turbo_profile_control',
                  args: [_bloc.snapshotTurboProfile.label],
                ),
                enabled: hasBlocks && !tapeLoading && !_bloc.preparing,
                onPressed: () => _showSnapshotProfileBottomSheet(context),
              )
            : TransportRateControl(
                label: '${(speedSnapshot.data ?? 1.0).toStringAsFixed(2)}x',
                semanticLabel: tr(
                  'playback_speed_control',
                  args: ['${(speedSnapshot.data ?? 1.0).toStringAsFixed(2)}x'],
                ),
                enabled: _bloc.policy.canChangeSpeed,
                onPressed: () => _showSliderBottomSheet(
                  context: context,
                  title: tr('adjust_speed'),
                  valueSuffix: 'x',
                  divisions: 375,
                  min: 0.25,
                  max: 4.0,
                  decimals: 2,
                  presets: const [
                    0.33,
                    0.5,
                    0.9,
                    1.0,
                    1.05,
                    1.1,
                    1.15,
                    2.0,
                    3.0,
                  ],
                  stream: _bloc.player.speedStream,
                  onChanged: _bloc.setSpeed,
                ),
              );
        return TapeTransportControls(
          policy: _bloc.policy,
          hasBlocks: hasBlocks,
          loading: tapeLoading,
          playing: playing,
          playbackCompleted: processingState == ProcessingState.completed,
          canStop: _bloc.player.position != Duration.zero,
          rateControl: rateControl,
          onPreviousBlock: _bloc.seekToPreviousBlock,
          onRestart: _bloc.policy.isSnapshot
              ? _bloc.restartFromBeginning
              : _bloc.seekToCurrentBlockStart,
          onNextBlock: _bloc.seekToNextBlock,
          onPlay: _bloc.play,
          onPause: _bloc.pause,
          onReplay: _bloc.replay,
          onStop: _bloc.stop,
          onShowBlocks: () => _showBlockBrowser(context),
        );
      },
    );
  }
}

class _PreparedPlayerAudio {
  const _PreparedPlayerAudio({
    required this.image,
    required this.wavPath,
    required this.response,
    this.snapshotProfile,
    this.snapshotIdentity,
    this.snapshotInvertPolarity,
    this.snapshotSampleRate,
  });

  final ResolvedTapeImage image;
  final String wavPath;
  final TapeConversionResponse response;
  final SnapshotTurboProfile? snapshotProfile;
  final SnapshotCacheIdentity? snapshotIdentity;
  final bool? snapshotInvertPolarity;
  final SnapshotAudioSampleRate? snapshotSampleRate;
}

class _CommittedSnapshotAudio {
  const _CommittedSnapshotAudio({
    required this.image,
    required this.wavPath,
    required this.blocks,
    required this.warnings,
    required this.profile,
    required this.identity,
    required this.invertPolarity,
    required this.sampleRate,
  });

  final ResolvedTapeImage image;
  final String wavPath;
  final List<TapeBlockInfo> blocks;
  final List<TapeConversionMessage> warnings;
  final SnapshotTurboProfile profile;
  final SnapshotCacheIdentity identity;
  final bool invertPolarity;
  final SnapshotAudioSampleRate sampleRate;
}

class _SnapshotPreparationException implements Exception {
  const _SnapshotPreparationException(this.message);

  final TapeConversionMessage message;
}

class _TapePlayerBloc {
  final SoftwareModel software;
  final TapePlayerMediaSelection _mediaSelection;

  List<String> get files => _mediaSelection.files;
  final AudioPlayer _player = AudioPlayer();
  final _backendService = getIt<BackendService>();
  final _wakeUpService = getIt<WakeLockControlService>();
  final _muteControlService = getIt<SilenceControlService>();
  final _volumeControlService = getIt<VolumeControlService>();
  final _settingsService = getIt<SettingsService>();
  final SnapshotCacheStore _snapshotCache = const SnapshotCacheStore();
  final SnapshotAssetLoader _snapshotAssetLoader = const SnapshotAssetLoader();
  StreamSubscription<AudioFilterType>? _filterSub;
  bool _pendingFilterRefresh = false;
  // Set when a filter change interrupts ongoing playback so that
  // _prepareTapeForPlay() can resume play() automatically after rebinding
  // the new WAV. Cleared on every consumption and on explicit stop/pause so
  // a user-initiated halt during a slow conversion is never overridden.
  bool _pendingAutoResume = false;

  List<TapeBlockInfo>? _blockInfos;
  TapeMediaKind? _mediaKind;
  ResolvedTapeImage? _resolvedImage;
  String? _currentWavPath;
  List<TapeConversionMessage> _currentWarnings = const [];
  SnapshotCacheIdentity? _currentSnapshotIdentity;
  late final SnapshotTurboProfileSession _snapshotProfileSession;
  final TapePlaybackSpeedCoordinator _speedCoordinator =
      TapePlaybackSpeedCoordinator();

  TapePlaybackPolicy get policy => TapePlaybackPolicy(_mediaKind);

  List<TapeBlockInfo>? get blockInfos => _blockInfos;

  int get currentFileIndex => _mediaSelection.currentIndex;

  String get filePath => _mediaSelection.currentFile;

  AudioPlayer get player => _player;

  bool _preparing = false;
  bool get preparing => _preparing || _snapshotProfileSession.preparing;
  SnapshotTurboProfile get snapshotTurboProfile =>
      _snapshotProfileSession.activeProfile;
  bool get snapshotInvertPolarity =>
      _snapshotProfileSession.activeInvertPolarity;
  SnapshotAudioSampleRate get snapshotSampleRate =>
      _snapshotProfileSession.activeSampleRate;

  final StreamController<TapePlayerData> _tapePlayerController =
      StreamController<TapePlayerData>();

  StreamSink<TapePlayerData> get tapePlayerSink => _tapePlayerController.sink;

  Stream<TapePlayerData> get tapePlayerStream => _tapePlayerController.stream;

  final StreamController<LoadingProgressData> _progressController =
      StreamController<LoadingProgressData>();

  StreamSink<LoadingProgressData> get progressSink => _progressController.sink;

  Stream<LoadingProgressData> get progressStream => _progressController.stream;

  _TapePlayerBloc(this.software, {TapePlayerController? controller})
    : _mediaSelection = TapePlayerMediaSelection(software) {
    final snapshotSignalSettings = _settingsService.snapshotSignalSettings;
    _snapshotProfileSession = SnapshotTurboProfileSession(
      initialProfile: snapshotSignalSettings.profile,
      initialInvertPolarity: snapshotSignalSettings.invertPolarity,
      initialSampleRate: snapshotSignalSettings.sampleRate,
      persistCommittedSettings: (profile, invertPolarity, sampleRate) =>
          _settingsService.setSnapshotSignalSettings(
            SnapshotSignalSettings(
              profile: profile,
              invertPolarity: invertPolarity,
              sampleRate: sampleRate,
            ),
          ),
    );
    controller?._prepareTapeImageExport = _prepareTapeImageExport;
    controller?._prepareWavExport = _prepareWavExport;
    controller?._prepareOriginalArchiveExport = _prepareOriginalArchiveExport;
    controller?._isWavReady = () => _blockInfos != null;
    controller?._isCurrentFileZip = () =>
        extension(filePath).toLowerCase() == '.zip';
    controller?._isSnapshot = () => policy.isSnapshot;

    _player.setVolume(1.00);
    currentFileIndex = software.currentFileIndex;
    _filterSub = _settingsService.filterChanges.listen((_) async {
      if (!policy.refreshOnFilterChange) return;
      // pause() (not stop()) keeps the audio session active and decoders
      // alive. just_audio's stop() calls _setPlatformActive(false), releasing
      // the platform; the next play() then races to re-activate the session
      // alongside setFilePath's pending load — a known issue still tagged
      // with a TODO in just_audio 0.10.5's play() implementation. The
      // user-visible symptom is "progress bar advances but no audio", until
      // a manual stop+play fully cycles the session. pause() avoids the race
      // entirely: the same active session is reused for the rebound WAV.
      final wasPlaying = _player.playing;
      await _player.pause();
      await _player.seek(Duration.zero);
      if (wasPlaying) _pendingAutoResume = true;
      if (_preparing) {
        // A prepare is in flight with a stale filter snapshot. Flag the
        // change so that prepare re-runs with the new filter before binding
        // the player. Calling _prepareTapeForPlay() here would return false
        // (because _preparing is true) and lose the update.
        _pendingFilterRefresh = true;
        return;
      }
      _blockInfos = null;
      await _prepareTapeForPlay();
    });
  }

  Future<Directory> _getCacheDirectory({required bool snapshot}) async {
    final supportPath = (await getApplicationSupportDirectory()).path;
    final path = (snapshot ? Definitions.snapshotDir : Definitions.tapeDir)
        .format([supportPath]);
    return Directory(path).create(recursive: true);
  }

  Future<String> _getTapeWavPath(
    AudioFilterType filter, {
    String? sourcePath,
  }) async {
    final selectedFilePath = sourcePath ?? filePath;
    // Use the application support directory rather than the temporary
    // directory: on Android the temp dir is the OS cache directory, which
    // the system can reclaim at any time — even mid-playback for a
    // foreground app. ExoPlayer reopens the underlying file whenever a
    // seek lands outside its playback buffer (~50s), so a reclaimed file
    // crashes long backward seeks with ENOENT. The application support
    // directory is internal app storage that the OS does not reclaim.
    final dir = await _getCacheDirectory(snapshot: false);
    // Hash the source path so the cache filename uses only [0-9a-f]
    // characters and never collides for different tapes. The filter name is
    // appended so switching filters yields distinct cached files instead of
    // replaying stale audio. The filter is passed in (rather than read from
    // the service inside) so a single prepare iteration always uses the same
    // filter for both the cache path and the conversion call.
    final hash = sha1.convert(utf8.encode(selectedFilePath)).toString();
    return Definitions.wafFilePath.format([dir.path, '${hash}_${filter.name}']);
  }

  Future<bool> _prepareTapeForPlay({bool force = true}) async {
    if (_preparing) return false;
    _preparing = true;
    final selectedFilePath = filePath;
    TapePlayerData? finalEvent;
    var success = false;
    try {
      final sourceBytes = software.isRemote
          ? await _backendService.downloadTape(selectedFilePath)
          : await File(selectedFilePath).readAsBytes();
      final image = resolveTapeImage((
        sourceBytes,
        selectedFilePath,
      ), model: _settingsService.zxModel);
      if (image.mediaKind == TapeMediaKind.snapshot) {
        final prepared = await _prepareSnapshotAudio(
          image: image,
          filePath: selectedFilePath,
          profile: _snapshotProfileSession.activeProfile,
          invertPolarity: _snapshotProfileSession.activeInvertPolarity,
          sampleRate: _snapshotProfileSession.activeSampleRate,
          force: force,
        );
        if (prepared != null) {
          final response = prepared.response;
          if (response.error != null) {
            finalEvent = TapePlayerData(
              TapePlayerState.error,
              selectedFilePath,
              error: response.error,
              mediaKind: response.mediaKind,
            );
          } else {
            await _bindPreparedSnapshot(prepared);
            _commitPreparedSnapshot(prepared);
            success = true;
            finalEvent = _idleEvent(prepared);
          }
        }
      } else {
        while (true) {
          final prepared = await _prepareOrdinaryAudio(
            image: image,
            filePath: selectedFilePath,
            force: force,
          );
          if (prepared == null) break;
          if (prepared.response.error != null) {
            finalEvent = TapePlayerData(
              TapePlayerState.error,
              selectedFilePath,
              error: prepared.response.error,
              mediaKind: prepared.response.mediaKind,
            );
            break;
          }
          final iterationFilter = _settingsService.audioFilter;
          await _speedCoordinator.applyFor(
            const TapePlaybackPolicy(TapeMediaKind.tape),
            _applySpeed,
          );
          await _player.setFilePath(prepared.wavPath);
          if (_pendingFilterRefresh &&
              _settingsService.audioFilter != iterationFilter) {
            continue;
          }
          _resolvedImage = image;
          _mediaKind = TapeMediaKind.tape;
          _currentWavPath = prepared.wavPath;
          _blockInfos = List.unmodifiable(prepared.response.blocks);
          _currentWarnings = List.unmodifiable(prepared.response.warnings);
          _currentSnapshotIdentity = null;
          success = true;
          finalEvent = _idleEvent(prepared);
          break;
        }
      }
    } catch (e) {
      finalEvent = TapePlayerData(
        TapePlayerState.error,
        selectedFilePath,
        message: e.toString(),
        mediaKind: _mediaKind,
      );
    } finally {
      _preparing = false;
    }
    if (finalEvent != null) _tapePlayerController.sink.add(finalEvent);
    if (success && _pendingAutoResume) {
      _pendingAutoResume = false;
      await _takeControl();
      await _player.play();
    }
    return success;
  }

  Future<_PreparedPlayerAudio?> _prepareSnapshotAudio({
    required ResolvedTapeImage image,
    required String filePath,
    required SnapshotTurboProfile profile,
    required bool invertPolarity,
    required SnapshotAudioSampleRate sampleRate,
    required bool force,
  }) async {
    final assets = await _snapshotAssetLoader.load();
    final identity = SnapshotCacheIdentity.create(
      image,
      assets,
      turboProfile: profile,
      invertPolarity: invertPolarity,
      sampleRate: sampleRate,
    );
    final paths = _snapshotCache.paths(
      (await _getCacheDirectory(snapshot: true)).path,
      identity,
    );
    final SnapshotCacheEntry? entry;
    if (force) {
      entry = await _snapshotCache.getOrCreate(
        paths,
        identity,
        (outputPath) => _convertResolvedImage(
          image: image,
          outputPath: outputPath,
          filePath: filePath,
          filter: _settingsService.audioFilter,
          snapshotAssets: assets,
          snapshotTurboProfile: profile,
          snapshotInvertPolarity: invertPolarity,
          snapshotSampleRate: sampleRate,
        ),
      );
    } else {
      entry = await _snapshotCache.read(paths, identity);
    }
    if (entry == null) return null;
    final prepared = _PreparedPlayerAudio(
      image: image,
      wavPath: entry.wavPath,
      response: entry.response,
      snapshotProfile: profile,
      snapshotIdentity: identity,
      snapshotInvertPolarity: invertPolarity,
      snapshotSampleRate: sampleRate,
    );
    if (prepared.response.isSuccess) _validatePreparedSnapshot(prepared);
    return prepared;
  }

  Future<_PreparedPlayerAudio?> _prepareOrdinaryAudio({
    required ResolvedTapeImage image,
    required String filePath,
    required bool force,
  }) async {
    _pendingFilterRefresh = false;
    final filter = _settingsService.audioFilter;
    final wavPath = await _getTapeWavPath(filter, sourcePath: filePath);
    final wavExists = await File(wavPath).exists();
    if (!wavExists && !force) return null;
    TapeConversionResponse? response;
    if (!wavExists ||
        _blockInfos == null ||
        _mediaKind != TapeMediaKind.tape ||
        _currentWavPath != wavPath) {
      response = await _convertResolvedImage(
        image: image,
        outputPath: wavPath,
        filePath: filePath,
        filter: filter,
      );
    }
    if (_pendingFilterRefresh && _settingsService.audioFilter != filter) {
      return _prepareOrdinaryAudio(
        image: image,
        filePath: filePath,
        force: force,
      );
    }
    response ??= TapeConversionResponse(
      mediaKind: TapeMediaKind.tape,
      blocks: _blockInfos ?? const [],
      warnings: _currentWarnings,
    );
    return _PreparedPlayerAudio(
      image: image,
      wavPath: wavPath,
      response: response,
    );
  }

  void _validatePreparedSnapshot(_PreparedPlayerAudio prepared) {
    final profile = prepared.snapshotProfile!;
    final identity = prepared.snapshotIdentity!;
    final invertPolarity = prepared.snapshotInvertPolarity!;
    final sampleRate = prepared.snapshotSampleRate!;
    final metadata = prepared.response.protocolMetadata;
    if (metadata == null ||
        metadata.turboProfileId != profile.id ||
        metadata.turboCatalogRevision !=
            SnapshotTurboProfiles.catalogRevision ||
        metadata.turboTimingFingerprint != profile.timingFingerprint ||
        metadata.invertedPolarity != invertPolarity ||
        metadata.sampleRateHz != sampleRate.hz ||
        metadata.wavProfile != identity.wavProfile ||
        identity.turboProfileId != profile.id ||
        identity.turboCatalogRevision !=
            SnapshotTurboProfiles.catalogRevision ||
        identity.turboTimingFingerprint != profile.timingFingerprint ||
        identity.invertedPolarity != invertPolarity ||
        identity.sampleRateHz != sampleRate.hz) {
      throw const FormatException(
        'Prepared snapshot profile metadata does not match its waveform',
      );
    }
  }

  Future<void> _bindPreparedSnapshot(_PreparedPlayerAudio prepared) async {
    await _speedCoordinator.applyFor(
      const TapePlaybackPolicy(TapeMediaKind.snapshot),
      _applySpeed,
    );
    await _player.setFilePath(prepared.wavPath);
    await _player.seek(Duration.zero);
  }

  void _commitPreparedSnapshot(_PreparedPlayerAudio prepared) {
    if (prepared.snapshotProfile != _snapshotProfileSession.activeProfile) {
      throw const FormatException(
        'Committed snapshot profile differs from the session profile',
      );
    }
    if (prepared.snapshotInvertPolarity !=
        _snapshotProfileSession.activeInvertPolarity) {
      throw const FormatException(
        'Committed snapshot polarity differs from the session polarity',
      );
    }
    if (prepared.snapshotSampleRate !=
        _snapshotProfileSession.activeSampleRate) {
      throw const FormatException(
        'Committed snapshot sample rate differs from the session sample rate',
      );
    }
    _resolvedImage = prepared.image;
    _mediaKind = TapeMediaKind.snapshot;
    _currentWavPath = prepared.wavPath;
    _blockInfos = List.unmodifiable(prepared.response.blocks);
    _currentWarnings = List.unmodifiable(prepared.response.warnings);
    _currentSnapshotIdentity = prepared.snapshotIdentity;
  }

  TapePlayerData _idleEvent(_PreparedPlayerAudio prepared) => TapePlayerData(
    TapePlayerState.idle,
    filePath,
    blocks: prepared.response.blocks,
    warnings: prepared.response.warnings,
    mediaKind: prepared.response.mediaKind,
  );

  Future<TapeConversionResponse> _convertResolvedImage({
    required ResolvedTapeImage image,
    required String outputPath,
    required String filePath,
    required AudioFilterType filter,
    SnapshotAssetBundle? snapshotAssets,
    SnapshotTurboProfile? snapshotTurboProfile,
    bool? snapshotInvertPolarity,
    SnapshotAudioSampleRate? snapshotSampleRate,
  }) async {
    _tapePlayerController.sink.add(
      TapePlayerData(
        TapePlayerState.loading,
        filePath,
        mediaKind: image.mediaKind,
      ),
    );
    final progressPort = ReceivePort();
    final progressSubscription = progressPort.listen((message) {
      if (message is int) {
        _progressController.sink.add(LoadingProgressData(filePath, message));
      }
    });
    try {
      return await compute(
        convertTapeImage,
        TapeConversionRequest(
          image: image,
          outputPath: outputPath,
          progressPort: progressPort.sendPort,
          audioFilterIndex: filter.index,
          snapshotAssets: snapshotAssets,
          snapshotTurboProfileId: snapshotTurboProfile?.id,
          snapshotTurboCatalogRevision: snapshotTurboProfile == null
              ? null
              : SnapshotTurboProfiles.catalogRevision,
          snapshotInvertPolarity: snapshotInvertPolarity,
          snapshotSampleRateHz: snapshotSampleRate?.hz,
        ),
      );
    } finally {
      await progressSubscription.cancel();
      progressPort.close();
    }
  }

  void _cleanWavCache() {
    getApplicationSupportDirectory()
        .then((dir) {
          var tapePath = Definitions.tapeDir.format([dir.path]);
          return Directory(tapePath);
        })
        .then((dir) async {
          if (await dir.exists()) await dir.delete(recursive: true);
        });
  }

  set currentFileIndex(int index) {
    if (currentFileIndex == index) return;
    _mediaSelection.select(index);
    // Completion leaves just_audio positioned at the end of the previous WAV.
    // Rewind immediately so a newly selected uncached option cannot replay the
    // completed source while its own preparation is deferred until Play.
    unawaited(_player.seek(Duration.zero));
    _blockInfos = null;
    _mediaKind = null;
    _resolvedImage = null;
    _currentWavPath = null;
    _currentWarnings = const [];
    _currentSnapshotIdentity = null;
    _pendingFilterRefresh = false;
    _pendingAutoResume = false;
    unawaited(_prepareTapeForPlay(force: false));
    _tapePlayerController.sink.add(
      TapePlayerData(TapePlayerState.indexChanged, filePath),
    );
  }

  Future play() async {
    if (shouldPrepareSelectedMedia(
      position: _player.position,
      hasBlocks: _blockInfos != null,
    )) {
      if (!await _prepareTapeForPlay()) return;
      await _takeControl();
    }
    await _player.play();
  }

  Future stop() async {
    // Cancel any in-flight auto-resume from a pending filter change — an
    // explicit stop during conversion must not be overridden.
    _pendingAutoResume = false;
    await _player.stop();
    await _player.seek(Duration.zero);
    await _looseControl();
  }

  Future pause() async {
    // Same rationale as stop(): user-pressed pause cancels pending resume.
    _pendingAutoResume = false;
    await _player.pause();
  }

  Future replay() async {
    await _player.seek(Duration.zero, index: _player.effectiveIndices.first);
  }

  /// Sets playback speed with tape-recorder semantics: pitch scales with
  /// speed (a 2x tape sounds an octave up). On iOS/macOS this is provided by
  /// the patched just_audio that selects AVAudioTimePitchAlgorithmVarispeed.
  /// On Android the same effect requires an explicit setPitch(speed) call.
  Future<void> setSpeed(double speed) async {
    await _speedCoordinator.select(speed, policy, _applySpeed);
  }

  Future<bool> selectSnapshotSignalSettings({
    required SnapshotTurboProfile profile,
    required bool invertPolarity,
    required SnapshotAudioSampleRate sampleRate,
  }) async {
    if (!policy.isSnapshot || _preparing) return false;
    if (profile == _snapshotProfileSession.activeProfile &&
        invertPolarity == _snapshotProfileSession.activeInvertPolarity &&
        sampleRate == _snapshotProfileSession.activeSampleRate) {
      return true;
    }

    final previous = _committedSnapshotAudio;
    final image = _resolvedImage;
    if (previous == null || image == null) return false;

    _preparing = true;
    _pendingAutoResume = false;
    final selectedFilePath = filePath;
    _tapePlayerController.sink.add(
      TapePlayerData(
        TapePlayerState.loading,
        selectedFilePath,
        blocks: previous.blocks,
        warnings: previous.warnings,
        mediaKind: TapeMediaKind.snapshot,
      ),
    );

    late TapePlayerData finalEvent;
    late bool success;
    try {
      final result = await _snapshotProfileSession.select<_PreparedPlayerAudio>(
        requestedProfile: profile,
        requestedInvertPolarity: invertPolarity,
        requestedSampleRate: sampleRate,
        stopAndRewind: () async {
          await _player.stop();
          await _player.seek(Duration.zero);
          await _looseControl();
        },
        prepare: (profile, invertPolarity, sampleRate) async {
          final prepared = await _prepareSnapshotAudio(
            image: image,
            filePath: selectedFilePath,
            profile: profile,
            invertPolarity: invertPolarity,
            sampleRate: sampleRate,
            force: true,
          );
          if (prepared == null) {
            throw StateError('Snapshot profile preparation returned no data');
          }
          final error = prepared.response.error;
          if (error != null) throw _SnapshotPreparationException(error);
          return prepared;
        },
        bind: _bindPreparedSnapshot,
        rollback: () => _restoreCommittedSnapshot(previous),
      );
      final prepared = result.prepared;
      if (result.committed && prepared != null) {
        _commitPreparedSnapshot(prepared);
        success = true;
        finalEvent = _idleEvent(prepared);
      } else {
        success = false;
        final error = result.error;
        final conversionError = error is _SnapshotPreparationException
            ? error.message
            : TapeConversionMessage(
                code: 'playerBinding',
                message: error.toString(),
              );
        finalEvent = TapePlayerData(
          TapePlayerState.error,
          selectedFilePath,
          error: conversionError,
          blocks: previous.blocks,
          warnings: previous.warnings,
          mediaKind: TapeMediaKind.snapshot,
        );
      }
    } catch (error) {
      await _restoreCommittedSnapshot(previous);
      success = false;
      finalEvent = TapePlayerData(
        TapePlayerState.error,
        selectedFilePath,
        error: TapeConversionMessage(
          code: 'playerBinding',
          message: error.toString(),
        ),
        blocks: previous.blocks,
        warnings: previous.warnings,
        mediaKind: TapeMediaKind.snapshot,
      );
    } finally {
      _preparing = false;
    }
    _tapePlayerController.sink.add(finalEvent);
    return success;
  }

  _CommittedSnapshotAudio? get _committedSnapshotAudio {
    final image = _resolvedImage;
    final wavPath = _currentWavPath;
    final blocks = _blockInfos;
    final identity = _currentSnapshotIdentity;
    if (!policy.isSnapshot ||
        image == null ||
        wavPath == null ||
        blocks == null ||
        identity == null) {
      return null;
    }
    return _CommittedSnapshotAudio(
      image: image,
      wavPath: wavPath,
      blocks: List.unmodifiable(blocks),
      warnings: List.unmodifiable(_currentWarnings),
      profile: _snapshotProfileSession.activeProfile,
      identity: identity,
      invertPolarity: _snapshotProfileSession.activeInvertPolarity,
      sampleRate: _snapshotProfileSession.activeSampleRate,
    );
  }

  Future<void> _restoreCommittedSnapshot(
    _CommittedSnapshotAudio previous,
  ) async {
    try {
      await _speedCoordinator.applyFor(
        const TapePlaybackPolicy(TapeMediaKind.snapshot),
        _applySpeed,
      );
      await _player.setFilePath(previous.wavPath);
      await _player.seek(Duration.zero);
    } catch (_) {
      // The original preparation/binding error remains the actionable one.
      // Committed profile metadata is deliberately left untouched.
    }
    _resolvedImage = previous.image;
    _mediaKind = TapeMediaKind.snapshot;
    _currentWavPath = previous.wavPath;
    _blockInfos = previous.blocks;
    _currentWarnings = previous.warnings;
    _currentSnapshotIdentity = previous.identity;
  }

  Future<void> _applySpeed(double speed) async {
    await applyPlaybackRate(
      speed: speed,
      isAndroid: Platform.isAndroid,
      setSpeed: _player.setSpeed,
      setPitch: _player.setPitch,
    );
  }

  Future seekToBlock(int blockIndex) async {
    if (!policy.canNavigateBlocks) return;
    if (_blockInfos == null || blockIndex >= _blockInfos!.length) return;
    var block = _blockInfos![blockIndex];
    await _player.seek(block.timeOffset);
    if (!_player.playing) {
      await _takeControl();
      await _player.play();
    }
  }

  /// Index of the block that contains the current player position, or null
  /// when blocks are not yet available. Blocks are sorted by timeOffset, so
  /// the current block is the last one whose start is at or before position.
  int? get currentBlockIndex {
    final blocks = _blockInfos;
    if (blocks == null || blocks.isEmpty) return null;
    final position = _player.position;
    int index = 0;
    for (int i = 0; i < blocks.length; i++) {
      if (blocks[i].timeOffset <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  /// Jumps to the previous block, or to the start of the current block when
  /// already on the first block.
  Future seekToPreviousBlock() async {
    if (!policy.canNavigateBlocks) return;
    final blocks = _blockInfos;
    if (blocks == null || blocks.isEmpty) return;
    final current = currentBlockIndex!;
    await seekToBlock((current - 1).clamp(0, blocks.length - 1));
  }

  /// Rewinds to the start of the block that's currently playing.
  Future seekToCurrentBlockStart() async {
    if (!policy.canNavigateBlocks) return;
    final current = currentBlockIndex;
    if (current == null) return;
    await seekToBlock(current);
  }

  /// Jumps to the next block, or stops playback when already on the last
  /// block.
  Future seekToNextBlock() async {
    if (!policy.canNavigateBlocks) return;
    final blocks = _blockInfos;
    if (blocks == null || blocks.isEmpty) return;
    final current = currentBlockIndex!;
    if (current >= blocks.length - 1) {
      await stop();
    } else {
      await seekToBlock(current + 1);
    }
  }

  Future restartFromBeginning() async {
    await _player.seek(Duration.zero);
    if (!_player.playing) {
      await _takeControl();
      await _player.play();
    }
  }

  void dispose() {
    _filterSub?.cancel();
    _looseControl()
        .then((value) => _cleanWavCache())
        .then((value) => _player.dispose())
        .then((value) => _progressController.close())
        .then((value) => _tapePlayerController.close());
  }

  Future<bool> downloadSelectedTape() async {
    if (!software.isRemote) return false;

    if (Platform.isAndroid) {
      // media_store_plus uses scoped MediaStore.Downloads on API ≥ 30 (no
      // permission needed) but falls back to direct File I/O on API ≤ 29,
      // which requires WRITE_EXTERNAL_STORAGE. On API 29 the manifest's
      // requestLegacyExternalStorage="true" reopens that path.
      final sdkInt = await MediaStore().getPlatformSDKInt();
      if (sdkInt < 30) {
        final status = await Permission.storage.request();
        if (!status.isGranted) return false;
      }
    }

    final url = filePath;
    final bytes = await _backendService.downloadTape(url);
    final fileName = basename(url);

    if (Platform.isAndroid) {
      final tmp = await getTemporaryDirectory();
      final stagedPath = '${tmp.path}/$fileName';
      await File(stagedPath).writeAsBytes(bytes, flush: true);

      final result = await MediaStore().saveFile(
        tempFilePath: stagedPath,
        dirType: DirType.download,
        dirName: DirName.download,
      );

      try {
        await File(stagedPath).delete();
      } catch (_) {}

      // SaveStatus.duplicated still means the bytes landed on disk — just
      // with a "(1)" suffix because something with the same name was already
      // there and the plugin couldn't delete it. From the user's standpoint
      // that's a successful save; only a null result is a real failure.
      return result != null;
    }

    final dir = Platform.isIOS
        ? await getApplicationDocumentsDirectory()
        : (await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory());
    final downloadPath = '${dir.path}/$fileName';
    await File(
      downloadPath,
    ).writeAsBytes(bytes, mode: FileMode.writeOnly, flush: true);
    return true;
  }

  Future<String> _prepareTapeImageExport() async {
    final selectedFilePath = filePath;
    Uint8List bytes;

    if (software.isRemote) {
      bytes = await _backendService.downloadTape(selectedFilePath);
    } else {
      bytes = await File(selectedFilePath).readAsBytes();
    }

    final image = resolveTapeImage((
      bytes,
      selectedFilePath,
    ), model: _settingsService.zxModel);
    _resolvedImage = image;

    final tmp = await getTemporaryDirectory();
    return stageTapeImageForExport(image, tmp.path);
  }

  Future<String> _prepareOriginalArchiveExport() async {
    final selectedFilePath = filePath;
    Uint8List bytes;

    if (software.isRemote) {
      bytes = await _backendService.downloadTape(selectedFilePath);
    } else {
      bytes = await File(selectedFilePath).readAsBytes();
    }

    final fileName = basename(selectedFilePath);
    final tmp = await getTemporaryDirectory();
    return stageTapeImageForExport(TapeImageData(bytes, fileName), tmp.path);
  }

  Future<String?> _prepareWavExport() async {
    final wavPath =
        _currentWavPath ?? await _getTapeWavPath(_settingsService.audioFilter);
    final wavFile = File(wavPath);
    if (!await wavFile.exists()) return null;

    final tapeFileName =
        _resolvedImage?.fileName ??
        basenameWithoutExtension(basename(filePath));
    final tmp = await getTemporaryDirectory();
    return stageWavForExport(
      cachedWavPath: wavFile.path,
      imageFileName: tapeFileName,
      temporaryDirectoryPath: tmp.path,
    );
  }

  Future _takeControl() async {
    await _volumeControlService.applySavedVolume();
    await _muteControlService.start();
    await _wakeUpService.start();
  }

  Future _looseControl() async {
    await _muteControlService.stop();
    await _wakeUpService.stop();
  }
}
