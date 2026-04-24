import 'package:shared_preferences/shared_preferences.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';

class ZxVolumeControlService extends VolumeControlService {
  static const _prefsKey = 'lastVolume';

  var _hasSet = false;

  @override
  Future applySavedVolume() async {
    if (_hasSet) return;
    _hasSet = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefsKey) ?? 1.0;
    VolumeController.instance.setVolume(saved);
    // Persist subsequent user-initiated changes so the next session
    // restores them. fetchInitialVolume is false so the listener does
    // not overwrite the just-applied value with the prior system level.
    VolumeController.instance.addListener(
      (volume) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_prefsKey, volume);
      },
      fetchInitialVolume: false,
    );
  }
}
