import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/services/whats_new_service.dart';
import 'package:zx_tape_player/ui/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({
      'headphoneWarningSeen': true,
      'whatsNewLastShownVersion': '1.6.1',
    });
    PackageInfo.setMockInitialValues(
      appName: 'ZX Tape Player',
      packageName: 'io.github.d00rsfan.zx_tape_player',
      version: '1.6.1',
      buildNumber: '12',
      buildSignature: '',
    );
    getIt.registerSingleton<WhatsNewService>(WhatsNewService());
  });

  tearDown(() => getIt.reset());

  testWidgets('home menu exposes settings but hides file-only actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: const _LocalizedTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home_menu_button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Tips'), findsOneWidget);
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('Open in browser'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Export…'), findsNothing);
  });
}

class _LocalizedTestApp extends StatelessWidget {
  const _LocalizedTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const HomeScreen(),
    );
  }
}
