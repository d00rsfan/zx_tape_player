import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the headphone warning per installation and release notes per version.
class WhatsNewService {
  static const _headphoneWarningSeenKey = 'headphoneWarningSeen';
  static const _lastShownVersionKey = 'whatsNewLastShownVersion';
  static const _neverShowAgainKey = 'whatsNewNeverShowAgain';

  Future<void>? _loading;
  late SharedPreferences _preferences;
  late String version;
  String? _lastShownVersion;
  bool _neverShowAgain = false;
  bool _shownThisSession = false;

  bool get shouldShowHeadphoneWarning =>
      !(_preferences.getBool(_headphoneWarningSeenKey) ?? false);

  Future<void> markHeadphoneWarningSeen() async {
    if (!await _preferences.setBool(_headphoneWarningSeenKey, true)) {
      throw StateError('Could not save the headphone warning preference');
    }
  }

  Future<void> resetNotices() async {
    await load();
    for (final key in [
      _headphoneWarningSeenKey,
      _lastShownVersionKey,
      _neverShowAgainKey,
    ]) {
      if (!await _preferences.remove(key)) {
        throw StateError('Could not reset the notice preference $key');
      }
    }
    _lastShownVersion = null;
    _neverShowAgain = false;
    _shownThisSession = false;
  }

  bool get neverShowAgain => _neverShowAgain;

  bool get shouldShowAutomatically =>
      version.isNotEmpty &&
      !_neverShowAgain &&
      !_shownThisSession &&
      _lastShownVersion != version;

  Future<void> load() async {
    try {
      await (_loading ??= _load());
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> _load() async {
    _preferences = await SharedPreferences.getInstance();
    // Build numbers can change without new release notes.
    version = (await PackageInfo.fromPlatform()).version;
    _lastShownVersion = _preferences.getString(_lastShownVersionKey);
    _neverShowAgain = _preferences.getBool(_neverShowAgainKey) ?? false;
  }

  /// Called after the changelog's first rendered frame, for either entry point.
  Future<void> markShown() async {
    _shownThisSession = true;
    if (version.isEmpty || _lastShownVersion == version) return;
    if (!await _preferences.setString(_lastShownVersionKey, version)) {
      throw StateError('Could not remember the displayed release');
    }
    _lastShownVersion = version;
  }

  Future<void> setNeverShowAgain(bool value) async {
    if (!await _preferences.setBool(_neverShowAgainKey, value)) {
      throw StateError('Could not save the release-notice preference');
    }
    _neverShowAgain = value;
  }
}
