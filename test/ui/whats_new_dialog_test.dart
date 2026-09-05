import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/services/whats_new_service.dart';
import 'package:zx_tape_player/ui/home_screen.dart';
import 'package:zx_tape_player/ui/widgets/whats_new_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WhatsNewService service;
  late String changelog;
  late Map<String, dynamic> translations;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    changelog = await File('CHANGELOG.md').readAsString();
    translations = jsonDecode(
      await File('assets/translations/en-US.json').readAsString(),
    ) as Map<String, dynamic>;
  });

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({'headphoneWarningSeen': true});
    PackageInfo.setMockInitialValues(
      appName: 'ZX Tape Player',
      packageName: 'io.github.d00rsfan.zx_tape_player',
      version: '1.6.1',
      buildNumber: '12',
      buildSignature: '',
    );
    service = WhatsNewService();
    getIt.registerSingleton<WhatsNewService>(service);
  });

  tearDown(() => getIt.reset());

  Future<void> pumpHome(WidgetTester tester, {AssetBundle? bundle}) async {
    addTearDown(() async {
      final dialog = find.byType(WhatsNewDialog);
      if (dialog.evaluate().isNotEmpty) {
        Navigator.of(tester.element(dialog)).pop();
        await tester.pumpAndSettle();
      }
    });
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        assetLoader: _TranslationLoader(translations),
        fallbackLocale: const Locale('en', 'US'),
        child: _LocalizedApp(bundle: bundle ?? _ChangelogBundle(changelog)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFromMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("What's new"));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first install shows the headphone warning then the changelog before the keyboard',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final warning = find.byKey(const ValueKey('headphone_warning_dialog'));
      await pumpHome(tester);
      expect(warning, findsOneWidget);
      expect(find.textContaining('100%'), findsOneWidget);
      expect(find.byType(WhatsNewDialog), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byKey(const ValueKey('headphone_warning_close')));
      await tester.pumpAndSettle();
      expect(warning, findsNothing);
      expect(find.byType(WhatsNewDialog), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      final firstRelease = changelog.indexOf('## ');
      expect(firstRelease, greaterThanOrEqualTo(0));
      expect(
        tester.widget<Markdown>(find.byType(Markdown)).data,
        changelog.substring(firstRelease),
      );
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('whatsNewLastShownVersion'), '1.6.1');

      await tester.tap(find.byKey(const ValueKey('whats_new_close')));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewDialog), findsNothing);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await getIt.unregister<WhatsNewService>();
      getIt.registerSingleton<WhatsNewService>(WhatsNewService());
      await pumpHome(tester);
      expect(warning, findsNothing);
      expect(find.byType(WhatsNewDialog), findsNothing);
    },
  );

  for (final dismissal in ['back', 'outside']) {
    testWidgets(
      '$dismissal dismissal counts and manual reopening still works',
      (tester) async {
        await pumpHome(tester);
        if (dismissal == 'back') {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tapAt(const Offset(2, 2));
        }
        await tester.pumpAndSettle();
        expect(find.byType(WhatsNewDialog), findsNothing);
        expect(service.shouldShowAutomatically, isFalse);
        await openFromMenu(tester);
        expect(find.byType(WhatsNewDialog), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('whats_new_close')));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('opt-out can be checked and reversed through the menu', (
    tester,
  ) async {
    await pumpHome(tester);
    final checkbox = find.byKey(const ValueKey('whats_new_never_show_again'));
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(service.neverShowAgain, isTrue);
    await tester.tap(find.byKey(const ValueKey('whats_new_close')));
    await tester.pumpAndSettle();

    await openFromMenu(tester);
    expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(service.neverShowAgain, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('whatsNewNeverShowAgain'), isFalse);
    await tester.tap(find.byKey(const ValueKey('whats_new_close')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'scroll reaches old releases while controls stay visible on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await pumpHome(tester);
      final close = find.byKey(const ValueKey('whats_new_close'));
      final checkbox = find.byKey(const ValueKey('whats_new_never_show_again'));
      final closeBefore = tester.getRect(close);
      final checkboxBefore = tester.getRect(checkbox);
      await tester.scrollUntilVisible(
        find.text('v1.0.15'),
        180,
        scrollable: find.descendant(
          of: find.byType(Markdown),
          matching: find.byType(Scrollable),
        ),
        maxScrolls: 300,
      );
      await tester.pumpAndSettle();
      expect(find.text('v1.0.15').hitTestable(), findsOneWidget);
      expect(tester.getRect(close), closeBefore);
      expect(tester.getRect(checkbox), checkboxBefore);
      expect(close.hitTestable(), findsOneWidget);
      expect(checkbox.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(close);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a missing changelog leaves the release unseen and Home usable', (
    tester,
  ) async {
    await pumpHome(tester, bundle: _ChangelogBundle(null));
    expect(find.byType(WhatsNewDialog), findsNothing);
    expect(service.shouldShowAutomatically, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('whatsNewLastShownVersion'), isNull);
    await openFromMenu(tester);
    expect(
      find.text('Could not load the release notes. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('the asset bundle contains the actual repository changelog', () async {
    expect(await rootBundle.loadString('CHANGELOG.md'), changelog);
  });
}

class _ChangelogBundle extends CachingAssetBundle {
  _ChangelogBundle(this.changelog);

  final String? changelog;

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != 'CHANGELOG.md') return rootBundle.loadString(key, cache: cache);
    if (changelog == null) throw StateError('Missing changelog');
    return changelog!;
  }
}

class _TranslationLoader extends AssetLoader {
  const _TranslationLoader(this.translations);

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      translations;
}

class _LocalizedApp extends StatelessWidget {
  const _LocalizedApp({required this.bundle});

  final AssetBundle bundle;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(),
    localizationsDelegates: context.localizationDelegates,
    supportedLocales: context.supportedLocales,
    locale: context.locale,
    home: DefaultAssetBundle(bundle: bundle, child: const HomeScreen()),
  );
}
