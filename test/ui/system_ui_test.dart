import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/services/whats_new_service.dart';
import 'package:zx_tape_player/ui/home_screen.dart';
import 'package:zx_tape_player/ui/splash_screen.dart';
import 'package:zx_tape_player/ui/tips_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'ZX Tape Player',
      packageName: 'io.github.d00rsfan.zx_tape_player',
      version: '1.6.1',
      buildNumber: '12',
      buildSignature: '',
    );
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({
      'headphoneWarningSeen': true,
      'whatsNewLastShownVersion': '1.6.1',
    });
    getIt.registerSingleton<WhatsNewService>(WhatsNewService());
  });

  tearDown(() => getIt.reset());

  testWidgets(
    'keeps transparent bars and light icons across app lifecycle UI',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      Map<dynamic, dynamic>? lastStyle;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            lastStyle = call.arguments as Map<dynamic, dynamic>;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      void expectReadableBars() {
        expect(lastStyle, isNotNull);
        expect(lastStyle!['statusBarColor'], 0);
        expect(lastStyle!['systemNavigationBarColor'], 0);
        expect(lastStyle!['statusBarIconBrightness'], 'Brightness.light');
        expect(
          lastStyle!['systemNavigationBarIconBrightness'],
          'Brightness.light',
        );
        expect(lastStyle!['systemStatusBarContrastEnforced'], isFalse);
        expect(lastStyle!['systemNavigationBarContrastEnforced'], isFalse);
      }

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en', 'US'),
          child: const ZxTapePlayer(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SplashScreen), findsOneWidget);
      expectReadableBars();

      // MaterialApp rebuilds on system theme changes. Its default light-theme
      // overlay must not replace our dark-background styling on the splash.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expectReadableBars();

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expectReadableBars();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed(TipsScreen.routeName);
      await tester.pumpAndSettle();
      expect(find.byType(TipsScreen), findsOneWidget);
      expectReadableBars();

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expectReadableBars();
      navigator.pop();
      await tester.pumpAndSettle();
      expectReadableBars();

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
