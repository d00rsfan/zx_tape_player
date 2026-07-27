import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/zx_control/zx_settings_service.dart';

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
}
