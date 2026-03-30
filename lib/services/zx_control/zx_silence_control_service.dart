import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';
import 'package:zx_tape_player/services/silence_control_service.dart';

class ZxSilenceControlService implements SilenceControlService {
  RingerModeStatus? _ringerMode;

  @override
  Future start() async {
    if (!Platform.isAndroid || _ringerMode != null) return;
    try {
      _ringerMode = await SoundMode.ringerModeStatus;
      await SoundMode.setSoundMode(RingerModeStatus.silent);
    } catch (e) {
      // DND access not granted - try requesting on first run
      var prefs = await SharedPreferences.getInstance();
      var initialized = prefs.getBool('dndAccessInitialized') ?? false;
      if (!initialized) {
        await prefs.setBool('dndAccessInitialized', true);
        // On newer Android, setting silent mode requires DND access
        // which will be prompted by the system automatically
      }
      _ringerMode = null;
    }
  }

  @override
  Future stop() async {
    if (_ringerMode == null) return;
    try {
      await SoundMode.setSoundMode(_ringerMode!);
    } catch (_) {
      // Best effort to restore
    }
    _ringerMode = null;
  }
}
