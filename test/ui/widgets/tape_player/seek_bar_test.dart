import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/seek_bar.dart';

void main() {
  testWidgets('timeline sliders are genuinely disabled without callbacks', (
    tester,
  ) async {
    await _pump(tester);

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(2));
    for (final slider in sliders) {
      expect(slider.onChanged, isNull);
      expect(slider.onChangeEnd, isNull);
    }
  });

  testWidgets('ordinary tape timeline retains seeking callbacks', (
    tester,
  ) async {
    var changes = 0;
    var ends = 0;
    await _pump(
      tester,
      onChanged: (_) => changes++,
      onChangeEnd: (_) => ends++,
    );

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    for (final slider in sliders) {
      expect(slider.onChanged, isNotNull);
      expect(slider.onChangeEnd, isNotNull);
      slider.onChanged!(25000);
      slider.onChangeEnd!(25000);
    }
    expect(changes, 2);
    expect(ends, 2);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  ValueChanged<Duration>? onChanged,
  ValueChanged<Duration>? onChangeEnd,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SeekBar(
        duration: const Duration(minutes: 2),
        position: const Duration(seconds: 20),
        bufferedPosition: const Duration(seconds: 40),
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    ),
  ),
);
