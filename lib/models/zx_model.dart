enum ZxModel {
  zxSpectrum(
    apiMachineType: 'ZXSPECTRUM',
    remoteTapeExtensions: <String>['tap', 'tzx'],
  ),
  zx81(
    apiMachineType: 'ZX81',
    remoteTapeExtensions: <String>['p', '81', 'p81', 'tzx'],
  ),
  zx80(
    apiMachineType: 'ZX80',
    remoteTapeExtensions: <String>['o', '80', 'tzx'],
  );

  const ZxModel({
    required this.apiMachineType,
    required this.remoteTapeExtensions,
  });

  final String apiMachineType;
  final List<String> remoteTapeExtensions;
}
