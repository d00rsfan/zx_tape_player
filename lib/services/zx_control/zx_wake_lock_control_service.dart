import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:zx_tape_player/services/wake_lock_service.dart';

class ZxWakeLockControlService extends WakeLockControlService {
  @override
  Future start() async {
    await WakelockPlus.enable();
  }

  @override
  Future stop() async {
    await WakelockPlus.disable();
  }
}
