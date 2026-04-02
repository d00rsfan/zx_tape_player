import 'package:volume_controller/volume_controller.dart';
import 'package:zx_tape_player/services/volume_control_service.dart';

class ZxVolumeControlService extends VolumeControlService {
  var _hasSet = false;

  @override
  Future setOptimalVolume() async {
    if (_hasSet) return;
    VolumeController.instance.setVolume(1.0);
    _hasSet = true;
  }
}
