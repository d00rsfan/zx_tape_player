import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_settings_service.dart';
import 'package:zx_tape_player/snapshots/snapshot_timing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to ZX Spectrum', () async {
    final settings = ZxSettingsService();

    await settings.load();

    expect(settings.zxModel, SettingsService.defaultZxModel);
    expect(settings.zxModel, ZxModel.zxSpectrum);
  });

  test('defaults snapshot signal settings to 5x standard', () async {
    final settings = ZxSettingsService();

    await settings.load();

    expect(
      settings.snapshotSignalSettings,
      SettingsService.defaultSnapshotSignalSettings,
    );
    expect(
      settings.snapshotSignalSettings.profile,
      SnapshotTurboProfiles.speed5x,
    );
    expect(settings.snapshotSignalSettings.invertPolarity, isFalse);
    expect(
      settings.snapshotSignalSettings.sampleRate,
      SnapshotAudioSampleRate.hz48k,
    );
  });

  test('loads a persisted ZX81 model', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zxModel': ZxModel.zx81.name,
    });
    final settings = ZxSettingsService();

    await settings.load();

    expect(settings.zxModel, ZxModel.zx81);
  });

  test('loads a persisted ZX80 model', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zxModel': ZxModel.zx80.name,
    });
    final settings = ZxSettingsService();

    await settings.load();

    expect(settings.zxModel, ZxModel.zx80);
  });

  test('persists changes and resets the model to ZX Spectrum', () async {
    final settings = ZxSettingsService();
    await settings.load();

    await settings.setZxModel(ZxModel.zx81);

    var prefs = await SharedPreferences.getInstance();
    expect(settings.zxModel, ZxModel.zx81);
    expect(prefs.getString('zxModel'), ZxModel.zx81.name);

    await settings.resetZxModelToDefault();

    prefs = await SharedPreferences.getInstance();
    expect(settings.zxModel, ZxModel.zxSpectrum);
    expect(prefs.getString('zxModel'), ZxModel.zxSpectrum.name);
  });

  test('falls back to ZX Spectrum for an unknown stored model', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'zxModel': 'unknown',
    });
    final settings = ZxSettingsService();

    await settings.load();

    expect(settings.zxModel, ZxModel.zxSpectrum);
  });

  test(
    'persists and restores snapshot speed, polarity, and sample rate together',
    () async {
      final firstSession = ZxSettingsService();
      await firstSession.load();
      const selected = SnapshotSignalSettings(
        profile: SnapshotTurboProfiles.speed2_5x,
        invertPolarity: true,
        sampleRate: SnapshotAudioSampleRate.hz44_1k,
      );

      await firstSession.setSnapshotSignalSettings(selected);

      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('snapshotSignalSettings')!),
        <String, Object>{
          'profileId': '2.5x',
          'invertPolarity': true,
          'sampleRateHz': 44100,
        },
      );

      final nextSession = ZxSettingsService();
      await nextSession.load();
      expect(nextSession.snapshotSignalSettings, selected);
    },
  );

  test(
    'falls back as a triple for malformed or obsolete snapshot settings',
    () async {
      const invalidValues = <Object>[
        'not-json',
        '{"profileId":"obsolete","invertPolarity":true}',
        '{"profileId":"2x","invertPolarity":"true"}',
        '{"profileId":"2x"}',
        '{"profileId":"2x","invertPolarity":true,"sampleRateHz":32000}',
        42,
      ];

      for (final stored in invalidValues) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'snapshotSignalSettings': stored,
        });
        final settings = ZxSettingsService();

        await settings.load();

        expect(
          settings.snapshotSignalSettings,
          SettingsService.defaultSnapshotSignalSettings,
          reason: stored.toString(),
        );
      }
    },
  );

  test('migrates the replaced 7.5x preset and preserves polarity', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'snapshotSignalSettings': '{"profileId":"7.5x","invertPolarity":true}',
    });
    final settings = ZxSettingsService();

    await settings.load();

    expect(
      settings.snapshotSignalSettings.profile,
      SnapshotTurboProfiles.speed7x,
    );
    expect(settings.snapshotSignalSettings.invertPolarity, isTrue);
    expect(
      settings.snapshotSignalSettings.sampleRate,
      SnapshotAudioSampleRate.hz48k,
    );
  });

  test('rejects non-catalog snapshot timing when persisting', () async {
    final settings = ZxSettingsService();
    await settings.load();

    expect(
      () => settings.setSnapshotSignalSettings(
        SnapshotSignalSettings(
          profile: SnapshotTurboProfiles.speed5x.copyWith(zeroTStates: 292),
          invertPolarity: true,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      settings.snapshotSignalSettings,
      SettingsService.defaultSnapshotSignalSettings,
    );
  });
}
