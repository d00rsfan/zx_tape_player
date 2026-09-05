import 'package:flutter/material.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/playback_policy.dart';
import 'package:zx_tape_player/utils/extensions.dart';

class TransportRateControl {
  const TransportRateControl({
    required this.label,
    required this.semanticLabel,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onPressed;
}

class TapeTransportControls extends StatelessWidget {
  const TapeTransportControls({
    super.key,
    required this.policy,
    required this.hasBlocks,
    required this.loading,
    required this.playing,
    required this.playbackCompleted,
    required this.canStop,
    required this.rateControl,
    required this.onPreviousBlock,
    required this.onRestart,
    required this.onNextBlock,
    required this.onPlay,
    required this.onPause,
    required this.onReplay,
    required this.onStop,
    required this.onShowBlocks,
  });

  final TapePlaybackPolicy policy;
  final bool hasBlocks;
  final bool loading;
  final bool playing;
  final bool playbackCompleted;
  final bool canStop;
  final TransportRateControl rateControl;
  final VoidCallback onPreviousBlock;
  final VoidCallback onRestart;
  final VoidCallback onNextBlock;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onReplay;
  final VoidCallback onStop;
  final VoidCallback onShowBlocks;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('previous_block_button'),
              color: Colors.white,
              disabledColor: HexColor('#546B7F'),
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 28.0,
              onPressed: hasBlocks && policy.canNavigateBlocks
                  ? onPreviousBlock
                  : null,
            ),
            IconButton(
              key: const ValueKey('restart_button'),
              color: Colors.white,
              disabledColor: HexColor('#546B7F'),
              icon: const Icon(Icons.restart_alt_rounded),
              iconSize: 28.0,
              onPressed: hasBlocks ? onRestart : null,
            ),
            IconButton(
              key: const ValueKey('next_block_button'),
              color: Colors.white,
              disabledColor: HexColor('#546B7F'),
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 28.0,
              onPressed: hasBlocks && policy.canNavigateBlocks
                  ? onNextBlock
                  : null,
            ),
            const SizedBox(width: 16.0),
            Container(
              width: 60.0,
              height: 60.0,
              decoration: BoxDecoration(
                color: HexColor('#28384C'),
                borderRadius: const BorderRadius.all(Radius.circular(30)),
              ),
              child: Builder(
                builder: (context) {
                  if (loading) {
                    return const Center(
                      child: SizedBox(
                        height: 40.0,
                        width: 40.0,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    );
                  }
                  if (!playing) {
                    return IconButton(
                      key: const ValueKey('play_button'),
                      color: Colors.white,
                      icon: const Icon(Icons.play_arrow_rounded),
                      iconSize: 40.0,
                      onPressed: onPlay,
                    );
                  }
                  if (!playbackCompleted) {
                    return IconButton(
                      key: const ValueKey('pause_button'),
                      color: Colors.white,
                      icon: const Icon(Icons.pause_rounded),
                      iconSize: 40.0,
                      onPressed: onPause,
                    );
                  }
                  return IconButton(
                    key: const ValueKey('replay_button'),
                    color: Colors.white,
                    icon: const Icon(Icons.replay_rounded),
                    iconSize: 40.0,
                    onPressed: onReplay,
                  );
                },
              ),
            ),
            const SizedBox(width: 16.0),
            IconButton(
              key: const ValueKey('stop_button'),
              color: Colors.white,
              disabledColor: HexColor('#546B7F'),
              icon: const Icon(Icons.stop_rounded),
              iconSize: 28.0,
              onPressed: canStop ? onStop : null,
            ),
            IconButton(
              key: const ValueKey('block_browser_button'),
              color: Colors.white,
              disabledColor: HexColor('#546B7F'),
              icon: const Icon(Icons.list_rounded),
              iconSize: 28.0,
              onPressed: hasBlocks ? onShowBlocks : null,
            ),
            IconButton(
              key: const ValueKey('speed_button'),
              tooltip: rateControl.semanticLabel,
              color: Colors.white,
              disabledColor: HexColor('#546B7F'),
              icon: Text(
                rateControl.label,
                style: TextStyle(
                  color: rateControl.enabled
                      ? Colors.white
                      : HexColor('#546B7F'),
                ),
              ),
              onPressed: rateControl.enabled ? rateControl.onPressed : null,
            ),
          ],
        ),
      ),
    );
  }
}
