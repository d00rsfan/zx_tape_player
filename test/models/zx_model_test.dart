import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/models/zx_model.dart';

void main() {
  test('ZX Spectrum uses Spectrum API filters', () {
    expect(ZxModel.zxSpectrum.apiMachineType, 'ZXSPECTRUM');
    expect(ZxModel.zxSpectrum.remoteTapeExtensions, <String>['tap', 'tzx']);
  });

  test('ZX81 uses the ZX81 P-file API filter', () {
    expect(ZxModel.zx81.apiMachineType, 'ZX81');
    expect(ZxModel.zx81.remoteTapeExtensions, <String>['p', '81', 'p81']);
  });

  test('ZX80 uses the ZX80 O-file API filter', () {
    expect(ZxModel.zx80.apiMachineType, 'ZX80');
    expect(ZxModel.zx80.remoteTapeExtensions, <String>['o', '80']);
  });
}
