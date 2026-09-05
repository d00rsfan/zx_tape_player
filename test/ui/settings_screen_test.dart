import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/models/pcm_sample_rate.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/services/whats_new_service.dart';
import 'package:zx_tape_player/ui/search_screen.dart';
import 'package:zx_tape_player/ui/settings_screen.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

late Map<String, dynamic> _translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    _translations = jsonDecode(
      await File('assets/translations/en-US.json').readAsString(),
    ) as Map<String, dynamic>;
  });

  late _FakeSettingsService settings;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({
      'headphoneWarningSeen': true,
      'whatsNewLastShownVersion': '1.6.1',
      'whatsNewNeverShowAgain': true,
    });
    PackageInfo.setMockInitialValues(
      appName: 'ZX Tape Player',
      packageName: 'io.github.d00rsfan.zx_tape_player',
      version: '1.6.1',
      buildNumber: '12',
      buildSignature: '',
    );
    getIt.registerSingleton<WhatsNewService>(WhatsNewService());
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

    await tester.scrollUntilVisible(find.text('ZX Spectrum'), -250);
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

  testWidgets('global frequency and polarity persist, reopen, and reset', (
    tester,
  ) async {
    await _pumpSettingsLauncher(tester, onSearch: (_) {});
    expect(find.text('Audio filter (TAP/TZX only)'), findsOneWidget);
    final signal = find.byKey(const ValueKey('settings_audio_signal'));
    await tester.scrollUntilVisible(signal, 250);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    final rates = find.byKey(const ValueKey('settings_sample_rate'));
    expect(tester.widget<SegmentedButton<PcmSampleRate>>(rates).selected, {
      PcmSampleRate.hz48k,
    });
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(find.text('Invert polarity (only for snapshots)'), findsOneWidget);
    final profile = settings.audioSignalSettings.profile;

    await tester.tap(find.text('44.1 kHz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invert polarity (only for snapshots)'));
    await tester.pumpAndSettle();
    expect(settings.audioSignalSettings.sampleRate, PcmSampleRate.hz44_1k);
    expect(settings.audioSignalSettings.invertPolarity, isTrue);
    expect(settings.audioSignalSettings.profile, profile);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_settings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(signal, 250);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<PcmSampleRate>>(rates).selected, {
      PcmSampleRate.hz44_1k,
    });
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    final reset = find.byKey(const ValueKey('settings_reset_default_button'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    final warning = find.byKey(const ValueKey('headphone_warning_dialog'));
    final notes = find.byKey(const ValueKey('whats_new_dialog'));
    expect(warning, findsOneWidget);
    expect(notes, findsNothing);
    await tester.tap(find.byKey(const ValueKey('headphone_warning_close')));
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
    expect(notes, findsOneWidget);
    final optOut = find.byKey(const ValueKey('whats_new_never_show_again'));
    expect(tester.widget<CheckboxListTile>(optOut).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('whats_new_close')));
    await tester.pumpAndSettle();
    final nextSession = WhatsNewService();
    await nextSession.load();
    expect(nextSession.shouldShowHeadphoneWarning, isFalse);
    expect(nextSession.shouldShowAutomatically, isFalse);
    expect(settings.audioSignalSettings.sampleRate, PcmSampleRate.hz48k);
    expect(settings.audioSignalSettings.invertPolarity, isFalse);
    expect(settings.audioSignalSettings.profile, profile);
  });

  testWidgets('signal controls fit a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpSettingsLauncher(tester, onSearch: (_) {});
    final polarity = find.byKey(const ValueKey('settings_invert_polarity'));
    await tester.scrollUntilVisible(polarity, 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(polarity).height,
      greaterThanOrEqualTo(kMinInteractiveDimension),
    );
    await tester.tap(polarity);
    await tester.pumpAndSettle();
    expect(settings.audioSignalSettings.invertPolarity, isTrue);
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
      assetLoader: const _TestAssetLoader(),
      child: _LocalizedTestApp(onSearch: onSearch),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open_settings')));
  await tester.pumpAndSettle();
}

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
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
  AudioSignalSettings audioSignalSettings =
      SettingsService.defaultAudioSignalSettings;

  int modelWrites = 0;
  int filterWrites = 0;

  @override
  Stream<AudioSignalSettings> get signalChanges =>
      const Stream<AudioSignalSettings>.empty();

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
  Future<void> setAudioSignalSettings(AudioSignalSettings settings) async {
    audioSignalSettings = settings;
  }
}

class _FakeVolumeControlService implements VolumeControlService {
  @override
  Future<void> applySavedVolume() async {}

  @override
  Future<void> resetToDefault() async {}
}
