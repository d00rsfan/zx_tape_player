import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:zx_tape_player/services/backend_service.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/silence_control_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/services/wake_lock_service.dart';
import 'package:zx_tape_player/services/whats_new_service.dart';
import 'package:zx_tape_player/services/zx_api/zxapi_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_settings_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_silence_control_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_volume_control_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_wake_lock_control_service.dart';
import 'package:zx_tape_player/ui/home_screen.dart';
import 'package:zx_tape_player/ui/player_screen.dart';
import 'package:zx_tape_player/ui/settings_screen.dart';
import 'package:zx_tape_player/ui/tips_screen.dart';
import 'package:zx_tape_player/utils/definitions.dart';
import 'package:zx_tape_player/utils/extensions.dart';

import 'ui/search_screen.dart';
import 'ui/splash_screen.dart';

final GetIt getIt = GetIt.instance;

// The app uses dark backgrounds even when the device uses a light theme.
// MaterialApp otherwise reapplies an opaque navigation bar and dark status
// icons when it builds, overriding the native window setup after startup.
const appSystemUiOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep Flutter's stored system UI mode aligned with MainActivity's native
  // window setup, including when Flutter restores overlays after a resume.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    JustAudioMediaKit.ensureInitialized(
      linux: Platform.isLinux,
      windows: Platform.isWindows,
    );
    JustAudioMediaKit.pitch = false;
  }

  if (!kIsWeb && Platform.isAndroid) {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = Definitions.appTitle;
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  getIt.registerLazySingleton<SilenceControlService>(
    () => ZxSilenceControlService(),
  );
  getIt.registerLazySingleton<WakeLockControlService>(
    () => ZxWakeLockControlService(),
  );
  getIt.registerLazySingleton<VolumeControlService>(
    () => ZxVolumeControlService(),
  );
  final settingsService = ZxSettingsService();
  await settingsService.load();
  getIt.registerSingleton<SettingsService>(settingsService);
  getIt.registerLazySingleton<WhatsNewService>(() => WhatsNewService());
  getIt.registerLazySingleton<BackendService>(
    () => ZxApiService(settingsService),
  );

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('cs', 'CZ'),
        Locale('da', 'DK'),
        Locale('es', 'ES'),
        Locale('it', 'IT'),
        Locale('nl', 'NL'),
        Locale('pt', 'PT'),
        Locale('ru', 'RU'),
        Locale('sk', 'SK'),
        Locale('uk', 'UA'),
        Locale('pl', 'PL'),
        Locale('sv', 'SE'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      // Fall back to en-US for any key missing in the current locale,
      // rather than rendering the raw key string. Keeps newly added UI
      // text readable even when translations for some locales lag behind.
      useFallbackTranslations: true,
      child: const ZxTapePlayer(),
    ),
  );
}

class ZxTapePlayer extends StatelessWidget {
  const ZxTapePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        ...context.localizationDelegates,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: Definitions.appTitle,
      theme: buildAppTheme(),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: appSystemUiOverlayStyle,
        // Third-party widgets still consume the Flutter SDK Material theme.
        // ignore: deprecated_member_use
        child: MaterialUiCompatibilityBridge(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const SplashScreen(),
      routes: {
        HomeScreen.routeName: (context) => const HomeScreen(),
        SearchScreen.routeName: (context) => const SearchScreen(),
        PlayerScreen.routeName: (context) => const PlayerScreen(),
        TipsScreen.routeName: (context) => const TipsScreen(),
        SettingsScreen.routeName: (context) => const SettingsScreen(),
      },
    );
  }
}

ThemeData buildAppTheme() => ThemeData(
  primaryColor: Colors.white,
  scaffoldBackgroundColor: HexColor('#546B7F'),
  visualDensity: VisualDensity.adaptivePlatformDensity,
  fontFamily: 'ZxSpectrum',
  appBarTheme: const AppBarThemeData(
    systemOverlayStyle: appSystemUiOverlayStyle,
  ),
  radioTheme: const RadioThemeData(
    fillColor: WidgetStatePropertyAll(Colors.white),
  ),
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? Colors.white
          : Colors.transparent,
    ),
    checkColor: const WidgetStatePropertyAll(Color(0xff28384c)),
    side: const BorderSide(color: Colors.white, width: 2.0),
  ),
);
