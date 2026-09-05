import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/services/whats_new_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _installedVersion('1.6.1');
  });

  test('first install stays eligible until the content is shown', () async {
    final service = WhatsNewService();
    await service.load();
    expect(service.shouldShowAutomatically, isTrue);
    expect(service.neverShowAgain, isFalse);

    final nextSession = WhatsNewService();
    await nextSession.load();
    expect(nextSession.shouldShowAutomatically, isTrue);

    await service.markShown();
    expect(service.shouldShowAutomatically, isFalse);
    final reopened = WhatsNewService();
    await reopened.load();
    expect(reopened.shouldShowAutomatically, isFalse);
  });

  test(
    'a new build does not repeat a release but a new version does',
    () async {
      final service = WhatsNewService();
      await service.load();
      await service.markHeadphoneWarningSeen();
      await service.markShown();

      _installedVersion('1.6.1', build: '13');
      final newBuild = WhatsNewService();
      await newBuild.load();
      expect(newBuild.shouldShowAutomatically, isFalse);

      _installedVersion('1.8.0', build: '20');
      final upgrade = WhatsNewService();
      await upgrade.load();
      expect(upgrade.shouldShowHeadphoneWarning, isFalse);
      expect(upgrade.shouldShowAutomatically, isTrue);
      await upgrade.markShown();
      expect(upgrade.shouldShowAutomatically, isFalse);
    },
  );

  test(
    'opt-out persists across releases and can be reversed manually',
    () async {
      final service = WhatsNewService();
      await service.load();
      await service.markShown();
      await service.setNeverShowAgain(true);

      _installedVersion('1.7.0');
      final upgrade = WhatsNewService();
      await upgrade.load();
      expect(upgrade.neverShowAgain, isTrue);
      expect(upgrade.shouldShowAutomatically, isFalse);

      // Manually opening the notes also counts as seeing the current release.
      await upgrade.markShown();
      await upgrade.setNeverShowAgain(false);
      final reopened = WhatsNewService();
      await reopened.load();
      expect(reopened.neverShowAgain, isFalse);
      expect(reopened.shouldShowAutomatically, isFalse);

      _installedVersion('1.8.0');
      final nextRelease = WhatsNewService();
      await nextRelease.load();
      expect(nextRelease.shouldShowAutomatically, isTrue);
    },
  );

  test('unknown package version never triggers an automatic notice', () async {
    _installedVersion('');
    final service = WhatsNewService();
    await service.load();
    expect(service.shouldShowAutomatically, isFalse);
  });
}

void _installedVersion(String version, {String build = '12'}) {
  PackageInfo.setMockInitialValues(
    appName: 'ZX Tape Player',
    packageName: 'io.github.d00rsfan.zx_tape_player',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
}
