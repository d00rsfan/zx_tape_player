abstract class VolumeControlService {
  static const double defaultVolume = 1.0;

  Future applySavedVolume();

  Future resetToDefault();
}
