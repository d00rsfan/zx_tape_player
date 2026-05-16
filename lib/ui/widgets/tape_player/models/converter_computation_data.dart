import 'dart:async';
import 'dart:io';

import 'package:zx_tape_player/services/backend_service.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

class ConverterComputationData {
  final String filePath;
  final bool isRemote;
  final File file;
  final BackendService backendService;
  final StreamController<dynamic> controller;
  final AudioFilterType audioFilter;

  ConverterComputationData(this.filePath, this.isRemote, this.file,
      this.backendService, this.controller, this.audioFilter);
}
