import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
    bool? selectedPolarity;
    SnapshotAudioSampleRate? selectedSampleRate;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        SnapshotTurboProfileSheet(
          title: 'Snapshot turbo rate',
          explanation: 'Transfer speed; playback remains at 1x.',
          activeProfile: SnapshotTurboProfiles.speed5x,
          invertPolarity: false,
          invertPolarityLabel: 'Invert polarity',
          sampleRate: SnapshotAudioSampleRate.hz48k,
          sampleRateLabel: 'Sample rate',
          onSelected: (profile) => selected = profile,
          onPolarityChanged: (value) => selectedPolarity = value,
          onSampleRateChanged: (value) => selectedSampleRate = value,
        ),
      ),
    );

    final buttons = tester
        .widgetList<RatePresetButton>(find.byType(RatePresetButton))
        .toList();
    expect(buttons.map((button) => button.label), [
      '10x',
      '7x',
      '5x',
      '4x',
      '3x',
      '2.5x',
      '2x',
      '1x',
    ]);
    expect(buttons.where((button) => button.selected).single.label, '5x');
    expect(find.byType(Slider), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
    expect(find.text('6x'), findsNothing);
    expect(find.text('Invert polarity'), findsOneWidget);
    expect(find.text('Sample rate'), findsOneWidget);
    expect(find.text('48 kHz'), findsOneWidget);
    expect(find.text('44.1 kHz'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<SnapshotAudioSampleRate>>(
            find.byKey(const ValueKey('snapshot_sample_rate')),
          )
          .selected,
      {SnapshotAudioSampleRate.hz48k},
    );
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(checkbox.fillColor, isNull);
    expect(checkbox.checkColor, isNull);
    final theme = Theme.of(tester.element(find.byType(Checkbox)));
    expect(theme.checkboxTheme.side?.color, Colors.white);
    expect(
      theme.checkboxTheme.fillColor?.resolve(const <WidgetState>{}),
      Colors.transparent,
    );
    expect(
      theme.checkboxTheme.fillColor?.resolve(const {WidgetState.selected}),
      Colors.white,
    );

    final selectedSemantics = tester.getSemantics(
      find.byKey(const ValueKey('snapshot_turbo_profile_5x')),
    );
    expect(selectedSemantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(selectedSemantics.label, contains('5x'));
    final checkboxSemantics = tester.semantics.find(
      find.bySemanticsLabel('Invert polarity'),
    );
    final checkboxData = checkboxSemantics.getSemanticsData();
    expect(checkboxData.flagsCollection.isChecked, ui.CheckedState.isFalse);

    await tester.tap(find.text('1x'));
    expect(selected, SnapshotTurboProfiles.speed1x);
    await tester.tap(find.byType(Checkbox));
    expect(selectedPolarity, isTrue);
    await tester.tap(find.text('44.1 kHz'));
    expect(selectedSampleRate, SnapshotAudioSampleRate.hz44_1k);
    semantics.dispose();
  });

  testWidgets('snapshot modal keeps the complete polarity row on screen', (
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
                  invertPolarity: false,
                  invertPolarityLabel: 'Инвертировать полярность',
                  sampleRate: SnapshotAudioSampleRate.hz48k,
                  sampleRateLabel: 'Частота дискретизации',
                  onSelected: (_) {},
                  onPolarityChanged: (_) {},
                  onSampleRateChanged: (_) {},
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
    final modal = tester.getRect(find.byType(BottomSheet));
    final polarity = tester.getRect(
      find.byKey(const ValueKey('snapshot_invert_polarity')),
    );
    expect(polarity.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(polarity.top, greaterThanOrEqualTo(modal.top));
    expect(polarity.bottom, lessThanOrEqualTo(modal.bottom));
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    backgroundColor: const Color(0xff3b4e63),
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);
