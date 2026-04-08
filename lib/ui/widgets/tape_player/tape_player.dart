import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/models/software_model.dart';
import 'package:zx_tape_player/services/backend_service.dart';
import 'package:zx_tape_player/services/silence_control_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/services/wake_lock_service.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/models/converter_computation_data.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/models/position_data.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/models/progress_model.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/models/tape_player_data.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/block_browser.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/seek_bar.dart';
import 'package:zx_tape_player/utils/bar_helper.dart';
import 'package:zx_tape_player/utils/definitions.dart';
import 'package:zx_tape_player/utils/extensions.dart';
import 'package:archive/archive.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class TapePlayer extends StatefulWidget {
  final SoftwareModel software;

  const TapePlayer({super.key, required this.software});

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

  @override
  void initState() {
    _bloc = _TapePlayerBloc(widget.software);
    super.initState();
  }

  @override
  void dispose() {
    _bloc.dispose();
    super.dispose();
  }

  _showSliderDialog({
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HexColor('#3B4E63'),
        title: Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(wordSpacing: 0.3, color: Colors.white)),
        content: StreamBuilder<double>(
          stream: stream,
          builder: (context, snapshot) {
            final value = snapshot.data ?? 1.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${value.toStringAsFixed(decimals)}$valueSuffix',
                    style: const TextStyle(
                        wordSpacing: 0.5,
                        fontSize: 24.0,
                        color: Colors.white)),
                const SizedBox(height: 16.0),
                SliderTheme(
                    data: SliderThemeData(
                        activeTickMarkColor: Colors.white,
                        activeTrackColor: Colors.white,
                        inactiveTickMarkColor: Colors.white,
                        inactiveTrackColor: HexColor('#546B7F'),
                        thumbColor: Colors.white),
                    child: Slider(
                      divisions: divisions,
                      min: min,
                      max: max,
                      value: value.clamp(min, max),
                      onChanged: onChanged,
                    )),
                if (presets != null) ...[
                  const SizedBox(height: 8.0),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: presets.map((preset) {
                      return TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: HexColor('#546B7F'),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 4.0),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                        ),
                        onPressed: () => onChanged(preset),
                        child: Text(preset.toStringAsFixed(decimals)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            );
          },
        ),
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
    if (filePath.contains('spectrumcomputing.co.uk')) return 'spectrumcomputing';
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
                            tapePlayerData?.state == TapePlayerState.Loading;
                        final carouselHeight =
                            _calculateCarouselHeight(context);
                        return Column(
                          children: [
                            Column(children: [
                              GestureDetector(
                                onLongPress: () async {
                                  HapticFeedback.vibrate();
                                  if (await _bloc.downloadSelectedTape()) {
                                    if (mounted) {
                                      BarHelper.showSnackBar(
                                          message: tr('download_tape_success'),
                                          context: context);
                                    }
                                  }
                                },
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0),
                                    width: double.infinity,
                                    height: carouselHeight,
                                    child: Container(
                                        decoration: BoxDecoration(
                                          color: HexColor('#172434'),
                                          borderRadius:
                                              BorderRadius.circular(3.5),
                                        ),
                                        child: CarouselSlider(
                                          items: _bloc.files
                                              .map((filePath) {
                                                final source = _getFileSource(filePath);
                                                return Container(
                                                  padding:
                                                      const EdgeInsets.all(
                                                          12.0),
                                                  child: Center(
                                                      child: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            basename(filePath),
                                                            style: _carouselNameStyle,
                                                            textAlign:
                                                                TextAlign.center,
                                                            overflow:
                                                                TextOverflow.ellipsis,
                                                            maxLines: 3,
                                                          ),
                                                          if (source.isNotEmpty)
                                                            Padding(
                                                              padding: const EdgeInsets.only(top: 2.0),
                                                              child: Text(
                                                                source,
                                                                style: _carouselSourceStyle,
                                                              ),
                                                          ),
                                                        ],
                                                      )),
                                                );
                                              })
                                              .toList(),
                                          options: CarouselOptions(
                                              scrollPhysics: _bloc.player
                                                              .position !=
                                                          Duration.zero ||
                                                      _bloc.files.length == 1 ||
                                                      tapeLoading
                                                  ? const NeverScrollableScrollPhysics()
                                                  : const AlwaysScrollableScrollPhysics(),
                                              autoPlay: false,
                                              enlargeCenterPage: false,
                                              height: carouselHeight,
                                              viewportFraction: 1.0,
                                              initialPage:
                                                  _bloc.currentFileIndex,
                                              onPageChanged:
                                                  (index, reason) async {
                                                _bloc.currentFileIndex = index;
                                              }),
                                        ))),
                              ),
                              Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16.0, horizontal: 16.0),
                                  child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 4.0,
                                      runSpacing: 4.0,
                                      children: _bloc.files
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                        final index = entry.key;
                                        return Container(
                                          width: 8.0,
                                          height: 8.0,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color:
                                                _bloc.currentFileIndex == index
                                                    ? HexColor('#D8DCE0')
                                                    : HexColor('#546B7F'),
                                          ),
                                        );
                                      }).toList())),
                            ]),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24.0),
                              child: StreamBuilder<Duration?>(
                                stream: _bloc.player.durationStream,
                                builder: (context, snapshot) {
                                  final duration =
                                      snapshot.data ?? Duration.zero;
                                  return StreamBuilder<PositionData>(
                                      stream: Rx.combineLatest2<Duration,
                                              Duration, PositionData>(
                                          _bloc.player.positionStream,
                                          _bloc.player.bufferedPositionStream,
                                          (position, bufferedPosition) =>
                                              PositionData(
                                                  position, bufferedPosition)),
                                      builder: (context, snapshot) {
                                        final positionData = snapshot.data ??
                                            PositionData(
                                                Duration.zero, Duration.zero);
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
                                            onChangeEnd: (newPosition) {
                                              _bloc.player.seek(newPosition);
                                            });
                                      });
                                },
                              ),
                            ),
                            _buildCurrentBlockRow(),
                            _buildControlButtons(
                                context, tapePlayerData, playerState),
                          ],
                        );
                      });
                })));
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
              onBlockTap: (index) {
                Navigator.pop(context);
                _bloc.seekToBlock(index);
              },
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
        return Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 24.0, vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 32.0,
                child: Text(
                  '${block.index + 1}',
                  maxLines: 2,
                  softWrap: true,
                  style: TextStyle(
                      color: HexColor('#B1B8C1'), fontSize: 11.0),
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
                          : FontWeight.normal),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButtons(BuildContext context,
      TapePlayerData? tapePlayerData, PlayerState? playerState) {
    if (tapePlayerData != null) {
      if (tapePlayerData.state == TapePlayerState.Error &&
          _bloc.filePath == tapePlayerData.filePath) {
        BarHelper.showSnackBar(
            message: tr('error_converting_tape_file'),
            barType: SnackBarType.error,
            context: context);
      }
    }

    final processingState = playerState?.processingState;
    final playing = playerState?.playing ?? false;
    final tapeLoading = tapePlayerData?.state == TapePlayerState.Loading;
    final hasBlocks = _bloc.blockInfos != null && _bloc.blockInfos!.isNotEmpty;

    // Two equal-flex Expanded halves around the play button so that PLAY is
    // always horizontally centered on screen, regardless of how much content
    // sits on either side. Left half right-aligns its children (block-nav
    // cluster sits flush against PLAY), right half left-aligns its children
    // (transport+utility cluster sits flush against PLAY).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  color: Colors.white,
                  disabledColor: HexColor('#546B7F'),
                  icon: const Icon(Icons.skip_previous_rounded),
                  iconSize: 28.0,
                  onPressed: hasBlocks ? _bloc.seekToPreviousBlock : null,
                ),
                IconButton(
                  color: Colors.white,
                  disabledColor: HexColor('#546B7F'),
                  icon: const Icon(Icons.restart_alt_rounded),
                  iconSize: 28.0,
                  onPressed: hasBlocks ? _bloc.seekToCurrentBlockStart : null,
                ),
                IconButton(
                  color: Colors.white,
                  disabledColor: HexColor('#546B7F'),
                  icon: const Icon(Icons.skip_next_rounded),
                  iconSize: 28.0,
                  onPressed: hasBlocks ? _bloc.seekToNextBlock : null,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Container(
            width: 60.0,
            height: 60.0,
            decoration: BoxDecoration(
              color: HexColor('#28384C'),
              borderRadius: const BorderRadius.all(Radius.circular(30)),
            ),
            child: Builder(builder: (context) {
              if (tapeLoading) {
                return const Center(
                    child: SizedBox(
                  height: 40.0,
                  width: 40.0,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                ));
              } else if (!playing) {
                return IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.play_arrow_rounded),
                    iconSize: 40.0,
                    onPressed: _bloc.play);
              } else if (processingState != ProcessingState.completed) {
                return IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.pause_rounded),
                  iconSize: 40.0,
                  onPressed: _bloc.pause,
                );
              } else {
                return IconButton(
                    color: Colors.white,
                    icon: const Icon(Icons.replay_rounded),
                    iconSize: 40.0,
                    onPressed: _bloc.replay);
              }
            }),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  color: Colors.white,
                  disabledColor: HexColor('#546B7F'),
                  icon: const Icon(Icons.stop_rounded),
                  iconSize: 40.0,
                  onPressed: _bloc.player.position != Duration.zero
                      ? _bloc.stop
                      : null,
                ),
                IconButton(
                  color: Colors.white,
                  disabledColor: HexColor('#546B7F'),
                  icon: const Icon(Icons.list_rounded),
                  iconSize: 28.0,
                  onPressed:
                      hasBlocks ? () => _showBlockBrowser(context) : null,
                ),
                StreamBuilder<double>(
                  stream: _bloc.player.speedStream,
                  builder: (context, snapshot) => IconButton(
                    color: Colors.white,
                    icon: Text("${snapshot.data?.toStringAsFixed(2)}x",
                        style: const TextStyle(color: Colors.white)),
                    onPressed: () {
                      _showSliderDialog(
                        context: context,
                        title: tr("adjust_speed"),
                        valueSuffix: "x",
                        divisions: 75,
                        min: 0.25,
                        max: 4.0,
                        decimals: 2,
                        presets: const [0.25, 0.33, 0.5, 1.0, 2.0, 3.0, 4.0],
                        stream: _bloc.player.speedStream,
                        onChanged: _bloc.setSpeed,
                      );
                    },
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TapePlayerBloc {
  final SoftwareModel software;

  List<String> get files => software.tapeFiles;
  int _currentFileIndex = 0;
  final AudioPlayer _player = AudioPlayer();
  final _backendService = getIt<BackendService>();
  final _wakeUpService = getIt<WakeLockControlService>();
  final _muteControlService = getIt<SilenceControlService>();
  final _volumeControlService = getIt<VolumeControlService>();

  List<TapeBlockInfo>? _blockInfos;

  List<TapeBlockInfo>? get blockInfos => _blockInfos;

  int get currentFileIndex => _currentFileIndex;

  String get filePath => files[_currentFileIndex];

  AudioPlayer get player => _player;

  bool _preparing = false;

  final StreamController<TapePlayerData> _tapePlayerController =
      StreamController<TapePlayerData>();

  StreamSink<TapePlayerData> get tapePlayerSink => _tapePlayerController.sink;

  Stream<TapePlayerData> get tapePlayerStream => _tapePlayerController.stream;

  final StreamController<LoadingProgressData> _progressController =
      StreamController<LoadingProgressData>();

  StreamSink<LoadingProgressData> get progressSink => _progressController.sink;

  Stream<LoadingProgressData> get progressStream => _progressController.stream;

  _TapePlayerBloc(this.software) {
    _player.setVolume(1.00);
    currentFileIndex = software.currentFileIndex;
  }

  static Future<List<TapeBlockInfo>> _getAndConvertImage(
      ConverterComputationData data) async {
    Uint8List bytes;
    if (data.isRemote) {
      bytes = await data.backendService.downloadTape(data.filePath);
    } else {
      bytes = await File(data.filePath).readAsBytes();
    }
    if (extension(data.filePath).toLowerCase() == '.zip') {
      bytes = _extractTapeFromZip(bytes);
    }
    var tape = await ZxTape.create(bytes);
    var result = await tape.toWavBytesWithBlocks(
        audioFilterType: AudioFilterType.bassBoost,
        frequency: Definitions.wavFrequency,
        progress: (percent) {
          var sink = LoadingProgressData(data.filePath, percent);
          data.controller.sink.add(sink);
        });
    await data.file.writeAsBytes(result.wavBytes);
    return result.blocks;
  }

  static Uint8List _extractTapeFromZip(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      if (file.isFile) {
        var ext = extension(file.name).toLowerCase();
        if (ext == '.tap' || ext == '.tzx') {
          return Uint8List.fromList(file.content as List<int>);
        }
      }
    }
    throw Exception('No tape file found in zip archive');
  }

  Future<String> _getWavPath() async {
    var filePath = files[_currentFileIndex];
    // Use the application support directory rather than the temporary
    // directory: on Android the temp dir is the OS cache directory, which
    // the system can reclaim at any time — even mid-playback for a
    // foreground app. ExoPlayer reopens the underlying file whenever a
    // seek lands outside its playback buffer (~50s), so a reclaimed file
    // crashes long backward seeks with ENOENT. The application support
    // directory is internal app storage that the OS does not reclaim.
    var wavPath = Definitions.tapeDir
        .format([(await getApplicationSupportDirectory()).path]);
    var dir = await Directory(wavPath).create(recursive: true);
    // Hash the source path so the cache filename uses only [0-9a-f]
    // characters and never collides for different tapes.
    final hash = sha1.convert(utf8.encode(filePath)).toString();
    return Definitions.wafFilePath.format([dir.path, hash]);
  }

  Future<bool> _prepareTapeForPlay({bool force = true}) async {
    if (_preparing) return false;
    _preparing = true;
    var filePath = files[_currentFileIndex];
    try {
      var wavFileName = await _getWavPath();
      var file = File(wavFileName);
      final wavExists = await file.exists();
      if (!wavExists && !force) {
        return false;
      }
      if (!wavExists || _blockInfos == null) {
        _tapePlayerController.sink
            .add(TapePlayerData(TapePlayerState.Loading, filePath));
        var convertModel = ConverterComputationData(filePath, software.isRemote,
            file, _backendService, _progressController);
        _blockInfos =
            await compute(_getAndConvertImage, convertModel);
      }
      await _player.setFilePath(wavFileName);
      _tapePlayerController.sink.add(TapePlayerData(
          TapePlayerState.Idle, filePath,
          blocks: _blockInfos));
      return true;
    } catch (e) {
      _tapePlayerController.sink.add(TapePlayerData(
          TapePlayerState.Error, filePath,
          message: e.toString()));
    } finally {
      _preparing = false;
    }
    return false;
  }

  void _cleanWavCache() {
    getApplicationSupportDirectory().then((dir) {
      var tapePath = Definitions.tapeDir.format([dir.path]);
      return Directory(tapePath);
    }).then((dir) async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
  }

  set currentFileIndex(int index) {
    if (_currentFileIndex == index) return;
    _currentFileIndex = index;
    _blockInfos = null;
    _prepareTapeForPlay(force: false);
    _tapePlayerController.sink.add(
        TapePlayerData(TapePlayerState.IndexChanged, files[_currentFileIndex]));
  }

  Future play() async {
    if (_player.position == Duration.zero) {
      if (!await _prepareTapeForPlay()) return;
      await _takeControl();
    }
    await _player.play();
  }

  Future stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    await _looseControl();
  }

  Future pause() async {
    await _player.pause();
  }

  Future replay() async {
    await _player.seek(Duration.zero,
        index: _player.effectiveIndices.first);
  }

  /// Sets playback speed with tape-recorder semantics: pitch scales with
  /// speed (a 2x tape sounds an octave up). On iOS/macOS this is provided by
  /// the patched just_audio that selects AVAudioTimePitchAlgorithmVarispeed.
  /// On Android the same effect requires an explicit setPitch(speed) call.
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    if (Platform.isAndroid) {
      try {
        await _player.setPitch(speed);
      } catch (_) {
        // setPitch may be unavailable on some Android backends; ignore.
      }
    }
  }

  Future seekToBlock(int blockIndex) async {
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
    final blocks = _blockInfos;
    if (blocks == null || blocks.isEmpty) return;
    final current = currentBlockIndex!;
    await seekToBlock((current - 1).clamp(0, blocks.length - 1));
  }

  /// Rewinds to the start of the block that's currently playing.
  Future seekToCurrentBlockStart() async {
    final current = currentBlockIndex;
    if (current == null) return;
    await seekToBlock(current);
  }

  /// Jumps to the next block, or stops playback when already on the last
  /// block.
  Future seekToNextBlock() async {
    final blocks = _blockInfos;
    if (blocks == null || blocks.isEmpty) return;
    final current = currentBlockIndex!;
    if (current >= blocks.length - 1) {
      await stop();
    } else {
      await seekToBlock(current + 1);
    }
  }

  void dispose() {
    _looseControl()
        .then((value) => _cleanWavCache())
        .then((value) => _player.dispose())
        .then((value) => _progressController.close())
        .then((value) => _tapePlayerController.close());
  }

  Future<bool> downloadSelectedTape() async {
    if (!software.isRemote) return false;

    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) return false;
    }

    var url = files[_currentFileIndex];
    var bytes = await _backendService.downloadTape(url);

    String? filePath;
    if (Platform.isAndroid) {
      var storagePath = (await getExternalStorageDirectory())?.path;
      if (storagePath == null) return false;
      filePath = '$storagePath/${Definitions.appTitle}/${basename(url)}';
      var dir = Directory(dirname(filePath));
      if (!dir.existsSync()) await dir.create(recursive: true);
    } else {
      var storagePath = (await getApplicationDocumentsDirectory()).path;
      filePath = '$storagePath/${basename(url)}';
    }
    if (filePath.isNullOrEmpty()) return false;

    await File(filePath)
        .writeAsBytes(bytes, mode: FileMode.writeOnly, flush: true);

    return true;
  }

  Future _takeControl() async {
    await _volumeControlService.setOptimalVolume();
    await _muteControlService.start();
    await _wakeUpService.start();
  }

  Future _looseControl() async {
    await _muteControlService.stop();
    await _wakeUpService.stop();
  }
}
