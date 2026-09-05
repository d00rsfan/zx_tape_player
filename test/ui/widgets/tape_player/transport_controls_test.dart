import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/services/tape_image_service.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/playback_policy.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/transport_controls.dart';

void main() {
  testWidgets('snapshot greys navigation and reuses rate control', (
    tester,
  ) async {
    var restarts = 0;
    var browsers = 0;
    var profiles = 0;
    await _pump(
      tester,
      policy: const TapePlaybackPolicy(TapeMediaKind.snapshot),
      hasBlocks: true,
      onRestart: () => restarts++,
      onShowBlocks: () => browsers++,
      onChangeSpeed: () => profiles++,
    );

    expect(_button(tester, 'previous_block_button').onPressed, isNull);
    expect(_button(tester, 'next_block_button').onPressed, isNull);
    expect(_button(tester, 'speed_button').onPressed, isNotNull);
    expect(_button(tester, 'restart_button').onPressed, isNotNull);
    expect(_button(tester, 'block_browser_button').onPressed, isNotNull);
    expect(
      _button(tester, 'previous_block_button').disabledColor?.toARGB32(),
      const Color(0xff546b7f).toARGB32(),
    );
    expect(
      tester.widget<Text>(find.text('5x')).style?.color?.toARGB32(),
      Colors.white.toARGB32(),
    );

    await tester.tap(find.byKey(const ValueKey('restart_button')));
    await tester.tap(find.byKey(const ValueKey('block_browser_button')));
    await tester.tap(find.byKey(const ValueKey('speed_button')));
    expect(restarts, 1);
    expect(browsers, 1);
    expect(profiles, 1);
    expect(
      _button(tester, 'speed_button').tooltip,
      'Snapshot turbo profile 5x',
    );
  });

  testWidgets('ordinary tapes retain speed and block navigation', (
    tester,
  ) async {
    var previous = 0;
    var next = 0;
    var speed = 0;
    await _pump(
      tester,
      policy: const TapePlaybackPolicy(TapeMediaKind.tape),
      hasBlocks: true,
      speed: 2.25,
      onPreviousBlock: () => previous++,
      onNextBlock: () => next++,
      onChangeSpeed: () => speed++,
    );

    expect(_button(tester, 'previous_block_button').onPressed, isNotNull);
    expect(_button(tester, 'next_block_button').onPressed, isNotNull);
    expect(_button(tester, 'speed_button').onPressed, isNotNull);
    expect(find.text('2.25x'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('previous_block_button')));
    await tester.tap(find.byKey(const ValueKey('next_block_button')));
    await tester.tap(find.byKey(const ValueKey('speed_button')));
    expect((previous, next, speed), (1, 1, 1));
  });

  testWidgets('all block controls are disabled without logical blocks', (
    tester,
  ) async {
    await _pump(
      tester,
      policy: const TapePlaybackPolicy(TapeMediaKind.tape),
      hasBlocks: false,
    );

    for (final key in <String>[
      'previous_block_button',
      'restart_button',
      'next_block_button',
      'block_browser_button',
    ]) {
      expect(_button(tester, key).onPressed, isNull, reason: key);
    }
  });

  testWidgets('snapshot profile control is grey while preparation is loading', (
    tester,
  ) async {
    await _pump(
      tester,
      policy: const TapePlaybackPolicy(TapeMediaKind.snapshot),
      hasBlocks: true,
      loading: true,
    );

    expect(_button(tester, 'speed_button').onPressed, isNull);
    expect(
      tester.widget<Text>(find.text('5x')).style?.color?.toARGB32(),
      const Color(0xff546b7f).toARGB32(),
    );
  });
}

IconButton _button(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(ValueKey<String>(key)));

Future<void> _pump(
  WidgetTester tester, {
  required TapePlaybackPolicy policy,
  required bool hasBlocks,
  bool loading = false,
  double speed = 1.0,
  VoidCallback? onPreviousBlock,
  VoidCallback? onRestart,
  VoidCallback? onNextBlock,
  VoidCallback? onShowBlocks,
  VoidCallback? onChangeSpeed,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xff3b4e63),
      body: TapeTransportControls(
        policy: policy,
        hasBlocks: hasBlocks,
        loading: loading,
        playing: false,
        playbackCompleted: false,
        canStop: false,
        rateControl: TransportRateControl(
          label: policy.isSnapshot ? '5x' : '${speed.toStringAsFixed(2)}x',
          semanticLabel: policy.isSnapshot
              ? 'Snapshot turbo profile 5x'
              : 'Playback speed ${speed.toStringAsFixed(2)}x',
          enabled: policy.isSnapshot
              ? hasBlocks && !loading
              : policy.canChangeSpeed,
          onPressed: onChangeSpeed ?? () {},
        ),
        onPreviousBlock: onPreviousBlock ?? () {},
        onRestart: onRestart ?? () {},
        onNextBlock: onNextBlock ?? () {},
        onPlay: () {},
        onPause: () {},
        onReplay: () {},
        onStop: () {},
        onShowBlocks: onShowBlocks ?? () {},
      ),
    ),
  ),
);
