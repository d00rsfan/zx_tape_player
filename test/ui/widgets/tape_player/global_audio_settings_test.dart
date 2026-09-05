import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/models/pcm_sample_rate.dart';
import 'package:zx_tape_player/models/software_model.dart';
import 'package:zx_tape_player/services/backend_service.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/silence_control_service.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';
import 'package:zx_tape_player/services/wake_lock_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_settings_service.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/tape_player.dart';

import '../../../snapshots/snapshot_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ZxSettingsService settings;
  late _AudioPlatform audio;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('player_global_audio_');
    SharedPreferences.setMockInitialValues({});
    settings = ZxSettingsService();
    await settings.load();
    await getIt.reset();
    getIt.registerSingleton<SettingsService>(settings);
    getIt.registerSingleton<BackendService>(_UnusedBackend());
    final controls = _Controls();
    getIt.registerSingleton<VolumeControlService>(controls);
    getIt.registerSingleton<SilenceControlService>(controls);
    getIt.registerSingleton<WakeLockControlService>(controls);
    audio = _AudioPlatform(directory.path)..install();
  });

  tearDown(() async {
    audio.uninstall();
    await getIt.reset();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<TapePlayerController> open(
    WidgetTester tester,
    String name,
    Uint8List bytes,
  ) async {
    final source = File('${directory.path}/$name');
    final software = await tester.runAsync(() async {
      await source.writeAsBytes(bytes);
      return SoftwareModel.createFromFile(source.path, 'Test');
    });
    final controller = TapePlayerController();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: TapePlayer(software: software!, controller: controller),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('play_button')));
    await _wait(tester, () => controller.isWavReady && audio.loads.isNotEmpty);
    return controller;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _wait(tester, () => audio.disposed);
  }

  testWidgets(
    'tape applies rate changes during binding and ignores inversion',
    (tester) async {
      await open(tester, 'test.tap', Uint8List.fromList([2, 0, 0, 0]));
      expect(audio.loads.last.rate, 48000);
      final initialLoads = audio.loads.length;
      await tester.runAsync(
        () => settings.setAudioSignalSettings(
          settings.audioSignalSettings.copyWith(invertPolarity: true),
        ),
      );
      await tester.pump();
      expect(audio.loads.length, initialLoads);

      final gate = Completer<void>();
      audio.nextLoadGate = gate.future;
      await tester.runAsync(
        () => settings.setAudioSignalSettings(
          settings.audioSignalSettings.copyWith(
            sampleRate: PcmSampleRate.hz44_1k,
          ),
        ),
      );
      await _wait(tester, () => audio.loads.length > initialLoads);
      expect(audio.loads.last.rate, 44100);
      await tester.runAsync(() async {
        await settings.setAudioSignalSettings(
          settings.audioSignalSettings.copyWith(
            sampleRate: PcmSampleRate.hz48k,
          ),
        );
        gate.complete();
      });
      await _wait(tester, () => audio.loads.last.rate == 48000);
      expect(audio.loads.map((load) => load.path).toSet().length, 2);
      await close(tester);
    },
  );

  testWidgets('open snapshot applies the latest global rate and polarity', (
    tester,
  ) async {
    await open(tester, 'test.z80', makeZ80V1());
    final standard = audio.loads.last.bytes;
    final gate = Completer<void>();
    audio.nextLoadGate = gate.future;
    await tester.runAsync(
      () => settings.setAudioSignalSettings(
        settings.audioSignalSettings.copyWith(
          sampleRate: PcmSampleRate.hz44_1k,
        ),
      ),
    );
    await _wait(tester, () => audio.loads.last.rate == 44100);
    await tester.runAsync(() async {
      await settings.setAudioSignalSettings(
        settings.audioSignalSettings.copyWith(
          sampleRate: PcmSampleRate.hz48k,
          invertPolarity: true,
        ),
      );
      gate.complete();
    });
    await _wait(
      tester,
      () => audio.loads.last.rate == 48000 && audio.loads.length >= 3,
    );
    final inverted = audio.loads.last.bytes;
    final length = ByteData.sublistView(standard).getUint32(40, Endian.little);
    expect(inverted.sublist(0, 44), standard.sublist(0, 44));
    expect(
      inverted.sublist(44, 44 + length),
      standard.sublist(44, 44 + length).map((value) => 255 - value),
    );
    expect(settings.audioSignalSettings.sampleRate, PcmSampleRate.hz48k);
    expect(settings.audioSignalSettings.invertPolarity, isTrue);
    await close(tester);
  });
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; !done() && attempt < 1000; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'Player did not finish the audio operation');
  await tester.pump();
}

class _LoadedWav {
  const _LoadedWav(this.path, this.bytes);
  final String path;
  final Uint8List bytes;
  int get rate => ByteData.sublistView(bytes).getUint32(24, Endian.little);
}

class _AudioPlatform {
  _AudioPlatform(this.directory);
  final String directory;
  final loads = <_LoadedWav>[];
  final _channels = <MethodChannel>[];
  Future<void>? nextLoadGate;
  bool disposed = false;

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void _mock(String name, Future<Object?> Function(MethodCall) handler) {
    final channel = MethodChannel(name);
    _channels.add(channel);
    _messenger.setMockMethodCallHandler(channel, handler);
  }

  void install() {
    _mock('plugins.flutter.io/path_provider', (_) async => directory);
    _mock(
      'com.ryanheise.audio_session',
      (call) async => call.method == 'getConfiguration' ? null : true,
    );
    _mock('com.ryanheise.just_audio.methods', (call) async {
      if (call.method == 'init') {
        final id = (call.arguments as Map)['id'];
        _mock('com.ryanheise.just_audio.events.$id', (_) async => null);
        _mock('com.ryanheise.just_audio.data.$id', (_) async => null);
        _mock('com.ryanheise.just_audio.methods.$id', (call) async {
          if (call.method == 'load') {
            final source = (call.arguments as Map)['audioSource'] as Map;
            final child = (source['children'] as List).first as Map;
            final file = File.fromUri(Uri.parse(child['uri'] as String));
            final bytes = await file.readAsBytes();
            loads.add(_LoadedWav(file.path, bytes));
            final gate = nextLoadGate;
            nextLoadGate = null;
            await gate;
            const duration = 10000000;
            _messenger.handlePlatformMessage(
              'com.ryanheise.just_audio.events.$id',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'processingState': 3,
                'updateTime': DateTime.now().millisecondsSinceEpoch,
                'updatePosition': 0,
                'bufferedPosition': duration,
                'duration': duration,
                'currentIndex': 0,
              }),
              (_) {},
            );
            return {'duration': duration};
          }
          return <String, Object>{};
        });
      } else if (call.method == 'disposePlayer') {
        disposed = true;
      }
      return <String, Object>{};
    });
  }

  void uninstall() {
    for (final channel in _channels) {
      _messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

class _UnusedBackend implements BackendService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controls
    implements
        VolumeControlService,
        SilenceControlService,
        WakeLockControlService {
  @override
  Future<void> applySavedVolume() async {}
  @override
  Future<void> resetToDefault() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}
