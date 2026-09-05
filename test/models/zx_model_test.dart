import 'package:flutter_test/flutter_test.dart';
import 'package:zx_tape_player/models/zx_model.dart';

void main() {
  test('ZX Spectrum uses tape and snapshot API filters', () {
    expect(ZxModel.zxSpectrum.apiMachineType, 'ZXSPECTRUM');
    expect(ZxModel.zxSpectrum.remoteTapeExtensions, <String>[
      'tap',
      'tzx',
      'z80',
      'sna',
    ]);
  });

  test('ZX81 uses P-file and TZX API filters', () {
    expect(ZxModel.zx81.apiMachineType, 'ZX81');
    expect(ZxModel.zx81.remoteTapeExtensions, <String>[
      'p',
      '81',
      'p81',
      'tzx',
    ]);
  });

  test('ZX80 uses O-file and TZX API filters', () {
    expect(ZxModel.zx80.apiMachineType, 'ZX80');
    expect(ZxModel.zx80.remoteTapeExtensions, <String>['o', '80', 'tzx']);
  });
}
