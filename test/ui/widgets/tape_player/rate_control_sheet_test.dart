import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/rate_control_sheet.dart';

void main() {
  testWidgets('ordinary sheet retains slider, steps, presets, and callbacks', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      _app(
        PlaybackSpeedSheet(
          title: 'Adjust speed',
          divisions: 375,
          min: 0.25,
          max: 4.0,
          valueSuffix: 'x',
          decimals: 2,
          presets: const [0.5, 1.0, 2.0],
          stream: Stream.value(1.0),
          onChanged: changes.add,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Adjust speed'), findsOneWidget);
    expect(find.text('1.00x'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byKey(const ValueKey('speed_decrease_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('speed_increase_button')), findsOneWidget);
    expect(find.byType(RatePresetButton), findsNWidgets(3));

    await tester.tap(find.text('2.00'));
    expect(changes.last, 2.0);
    await tester.tap(find.byKey(const ValueKey('speed_decrease_button')));
    expect(changes.last, closeTo(0.99, 0.0001));
  });

  testWidgets('snapshot sheet is ordered, discrete, selected, and accessible', (
    tester,
  ) async {
    SnapshotTurboProfile? selected;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        SnapshotTurboProfileSheet(
          title: 'Snapshot turbo rate',
          explanation: 'Transfer speed; playback remains at 1x.',
          activeProfile: SnapshotTurboProfiles.speed5x,
          onSelected: (profile) => selected = profile,
        ),
      ),
    );

    final buttons = tester
        .widgetList<RatePresetButton>(find.byType(RatePresetButton))
        .toList();
    expect(buttons.map((button) => button.label), [
      '11.3x',
      '6.9x',
      '5.7x',
      '4.6x',
      '3.3x',
      '2.8x',
      '2.3x',
      '1.1x',
    ]);
    expect(buttons.where((button) => button.selected).single.label, '5.7x');
    expect(find.byType(Slider), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
    expect(find.text('6x'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('48 kHz'), findsNothing);
    expect(find.text('44.1 kHz'), findsNothing);

    final selectedSemantics = tester.getSemantics(
      find.byKey(const ValueKey('snapshot_turbo_profile_5x')),
    );
    expect(selectedSemantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(selectedSemantics.label, contains('5.7x'));
    await tester.tap(find.text('1.1x'));
    expect(selected, SnapshotTurboProfiles.speed1x);
    semantics.dispose();
  });

  testWidgets('snapshot modal keeps its speed choices on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open_snapshot_sheet'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => SnapshotTurboProfileSheet(
                  title: 'Скорость сигнала снапшота',
                  explanation:
                      'Выберите скорость передачи относительно '
                      'стандартной загрузки с ленты. Воспроизведение '
                      'остаётся 1x.',
                  activeProfile: SnapshotTurboProfiles.speed5x,
                  sampleRate: SnapshotAudioSampleRate.hz44_1k,
                  onSelected: (_) {},
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open_snapshot_sheet')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('12.6x'), findsOneWidget);
    expect(find.text('5.3x'), findsOneWidget);
    final modal = tester.getRect(find.byType(BottomSheet));
    final lastChoice = tester.getRect(
      find.byKey(const ValueKey('snapshot_turbo_profile_1x')),
    );
    expect(lastChoice.top, greaterThanOrEqualTo(modal.top));
    expect(lastChoice.bottom, lessThanOrEqualTo(modal.bottom));
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    backgroundColor: const Color(0xff3b4e63),
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);
