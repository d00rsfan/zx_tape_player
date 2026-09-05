import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/ui/search_screen.dart';
import 'package:zx_tape_player/ui/settings_screen.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  late _FakeSettingsService settings;

  setUp(() async {
    await getIt.reset();
    settings = _FakeSettingsService();
    getIt.registerSingleton<SettingsService>(settings);
    getIt.registerSingleton<VolumeControlService>(_FakeVolumeControlService());
  });

  tearDown(() => getIt.reset());

  testWidgets('settings controls align and changes open a fresh search', (
    tester,
  ) async {
    Object? searchArguments;
    await _pumpSettingsLauncher(
      tester,
      onSearch: (arguments) => searchArguments = arguments,
    );

    await tester.ensureVisible(find.text('None'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(settings.audioFilter, AudioFilterType.none);
    expect(settings.filterWrites, 1);

    final resetButton = find.byKey(
      const ValueKey('settings_reset_default_button'),
    );
    await tester.scrollUntilVisible(resetButton, 200.0);
    await tester.pumpAndSettle();

    final lastFilterRadio = find
        .byWidgetPredicate((widget) => widget is Radio<AudioFilterType>)
        .last;
    final resetIcon = find.descendant(
      of: resetButton,
      matching: find.byIcon(Icons.restart_alt_rounded),
    );
    expect(
      tester.getCenter(resetIcon).dx,
      closeTo(tester.getCenter(lastFilterRadio).dx, 0.01),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('ZX80'), findsOneWidget);
    await tester.tap(find.text('ZX Spectrum'));
    await tester.pumpAndSettle();
    expect(settings.modelWrites, 0);
    expect(searchArguments, isNull);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('ZX81'));
    await tester.pumpAndSettle();

    expect(settings.zxModel, ZxModel.zx81);
    expect(searchArguments, '');
    expect(find.byKey(const ValueKey('fresh_search')), findsOneWidget);
  });
}

Future<void> _pumpSettingsLauncher(
  WidgetTester tester, {
  required ValueChanged<Object?> onSearch,
}) async {
  // Recreate the Navigator for each test instead of retaining the route stack
  // from the previous EasyLocalization/MaterialApp tree.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    EasyLocalization(
      key: UniqueKey(),
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      child: _LocalizedTestApp(onSearch: onSearch),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open_settings')));
  await tester.pumpAndSettle();
}

class _LocalizedTestApp extends StatelessWidget {
  const _LocalizedTestApp({required this.onSearch});

  final ValueChanged<Object?> onSearch;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const _SettingsLauncher(),
      routes: {
        SettingsScreen.routeName: (context) => const SettingsScreen(),
        SearchScreen.routeName: (context) {
          onSearch(ModalRoute.of(context)?.settings.arguments);
          return const Scaffold(
            key: ValueKey('fresh_search'),
            body: SizedBox.shrink(),
          );
        },
      },
    );
  }
}

class _SettingsLauncher extends StatelessWidget {
  const _SettingsLauncher();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('open_settings'),
          onPressed: () =>
              Navigator.of(context).pushNamed(SettingsScreen.routeName),
          child: const Text('Open settings'),
        ),
      ),
    );
  }
}

class _FakeSettingsService implements SettingsService {
  @override
  AudioFilterType audioFilter = SettingsService.defaultAudioFilter;

  @override
  ZxModel zxModel = SettingsService.defaultZxModel;

  @override
  SnapshotSignalSettings snapshotSignalSettings =
      SettingsService.defaultSnapshotSignalSettings;

  int modelWrites = 0;
  int filterWrites = 0;

  @override
  Stream<AudioFilterType> get filterChanges =>
      const Stream<AudioFilterType>.empty();

  @override
  Future<void> load() async {}

  @override
  Future<void> resetAudioFilterToDefault() async {
    audioFilter = SettingsService.defaultAudioFilter;
  }

  @override
  Future<void> resetZxModelToDefault() async {
    zxModel = SettingsService.defaultZxModel;
  }

  @override
  Future<void> setAudioFilter(AudioFilterType filter) async {
    filterWrites++;
    audioFilter = filter;
  }

  @override
  Future<void> setZxModel(ZxModel model) async {
    modelWrites++;
    zxModel = model;
  }

  @override
  Future<void> setSnapshotSignalSettings(
    SnapshotSignalSettings settings,
  ) async {
    snapshotSignalSettings = settings;
  }
}

class _FakeVolumeControlService implements VolumeControlService {
  @override
  Future<void> applySavedVolume() async {}

  @override
  Future<void> resetToDefault() async {}
}
