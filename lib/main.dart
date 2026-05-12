import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:zx_tape_player/services/backend_service.dart';
import 'package:zx_tape_player/services/silence_control_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/services/wake_lock_service.dart';
import 'package:zx_tape_player/services/zx_api/zxapi_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_silence_control_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_volume_control_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_wake_lock_control_service.dart';
import 'package:zx_tape_player/ui/home_screen.dart';
import 'package:zx_tape_player/ui/player_screen.dart';
import 'package:zx_tape_player/ui/tips_screen.dart';
import 'package:zx_tape_player/utils/definitions.dart';
import 'package:zx_tape_player/utils/extensions.dart';

import 'ui/search_screen.dart';
import 'ui/splash_screen.dart';

final GetIt getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // systemNavigationBarColor is intentionally omitted: it routes through
  // Window.setNavigationBarColor(), which Android deprecated in API 35.
  // Edge-to-edge (enabled in MainActivity.onCreate) makes the bar
  // transparent and lets the app paint underneath; only the bar-icon
  // brightness still needs to be configured explicitly.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  getIt.registerLazySingleton<BackendService>(() => ZxApiService());
  getIt.registerLazySingleton<SilenceControlService>(
      () => ZxSilenceControlService());
  getIt.registerLazySingleton<WakeLockControlService>(
      () => ZxWakeLockControlService());
  getIt.registerLazySingleton<VolumeControlService>(
      () => ZxVolumeControlService());

  await EasyLocalization.ensureInitialized();

  runApp(EasyLocalization(
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
        Locale('sv', 'SE')
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      child: const ZxTapePlayer()));
}

class ZxTapePlayer extends StatelessWidget {
  const ZxTapePlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        title: Definitions.appTitle,
        theme: ThemeData(
          primaryColor: Colors.white,
          scaffoldBackgroundColor: HexColor('#546B7F'),
          visualDensity: VisualDensity.adaptivePlatformDensity,
          fontFamily: 'ZxSpectrum',
        ),
        home: const SplashScreen(),
        routes: {
          HomeScreen.routeName: (context) => const HomeScreen(),
          SearchScreen.routeName: (context) => const SearchScreen(),
          PlayerScreen.routeName: (context) => const PlayerScreen(),
          TipsScreen.routeName: (context) => const TipsScreen(),
        });
  }
}
