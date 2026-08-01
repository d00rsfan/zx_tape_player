import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zx_tape_player/models/zx_model.dart';
import 'package:zx_tape_player/services/settings_service.dart';
import 'package:zx_tape_player/services/zx_api/zxapi_service.dart';
import 'package:zx_tape_player/utils/api_base_helper.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

void main() {
  late _FakeSettingsService settings;
  late _RecordingApiBaseHelper helper;
  late ZxApiService service;

  setUp(() {
    settings = _FakeSettingsService();
    helper = _RecordingApiBaseHelper();
    service = ZxApiService(settings, helper: helper);
  });

  test('uses the selected model for title suggestions', () async {
    await service.fetchTermsList('manic miner');

    expect(
      helper.urls.single,
      '/suggest/manic+miner?machinetype=ZXSPECTRUM&contenttype=SOFTWARE',
    );

    helper.urls.clear();
    settings.zxModel = ZxModel.zx81;
    await service.fetchTermsList('3d');

    expect(
      helper.urls.single,
      '/suggest/3d?machinetype=ZX81&contenttype=SOFTWARE',
    );

    helper.urls.clear();
    settings.zxModel = ZxModel.zx80;
    await service.fetchTermsList('chess');

    expect(
      helper.urls.single,
      '/suggest/chess?machinetype=ZX80&contenttype=SOFTWARE',
    );
  });

  test('uses Spectrum machine and tape filters by default', () async {
    await service.fetchHitsList('jetpac', 30, offset: 2);

    expect(
      helper.urls.single,
      '/search/titles/jetpac?mode=tiny&sort=rel_desc&contenttype=SOFTWARE'
      '&machinetype=ZXSPECTRUM&size=30&offset=2&tosectype=tap&tosectype=tzx',
    );
  });

  test('uses ZX81 machine, P-file, and TZX filters when selected', () async {
    settings.zxModel = ZxModel.zx81;

    await service.fetchHitsList('3d', 30);

    expect(
      helper.urls.single,
      '/search/titles/3d?mode=tiny&sort=rel_desc&contenttype=SOFTWARE'
      '&machinetype=ZX81&size=30&offset=0&tosectype=p&tosectype=81'
      '&tosectype=p81&tosectype=tzx',
    );
  });

  test('uses ZX80 machine, O-file, and TZX filters when selected', () async {
    settings.zxModel = ZxModel.zx80;

    await service.fetchHitsList('chess', 30);

    expect(
      helper.urls.single,
      '/search/titles/chess?mode=tiny&sort=rel_desc&contenttype=SOFTWARE'
      '&machinetype=ZX80&size=30&offset=0&tosectype=o&tosectype=80'
      '&tosectype=tzx',
    );
  });

  test(
    'applies the selected machine to publisher and letter searches',
    () async {
      settings.zxModel = ZxModel.zx81;

      await service.fetchHitsList(' Greye', 30);
      await service.fetchHitsList('A', 30);

      expect(helper.urls, <String>[
        '/entries/bypublisher/Greye?mode=tiny&sort=title_asc'
            '&contenttype=SOFTWARE&machinetype=ZX81&size=30&offset=0'
            '&tosectype=p&tosectype=81&tosectype=p81&tosectype=tzx',
        '/entries/byletter/A?mode=tiny&contenttype=SOFTWARE'
            '&machinetype=ZX81&size=30&offset=0&tosectype=p&tosectype=81'
            '&tosectype=p81&tosectype=tzx',
      ]);
    },
  );

  test(
    'normalizes letters and falls back to title search for every model',
    () async {
      for (final model in ZxModel.values) {
        settings.zxModel = model;
        helper.urls.clear();
        helper.failOnceForPrefix = '/entries/byletter/';

        await service.fetchHitsList('a', 30);

        final filters = model.remoteTapeExtensions
            .map((extension) => '&tosectype=$extension')
            .join();
        expect(helper.urls, <String>[
          '/entries/byletter/A?mode=tiny&contenttype=SOFTWARE'
              '&machinetype=${model.apiMachineType}&size=30&offset=0$filters',
          '/search/titles/A?mode=tiny&sort=rel_desc&contenttype=SOFTWARE'
              '&machinetype=${model.apiMachineType}&size=30&offset=0$filters',
        ], reason: model.name);
      }
    },
  );

  test('ignores malformed screen arrays for every model', () async {
    helper.response = <String, dynamic>{
      'hits': <String, dynamic>{
        'hits': <dynamic>[
          <String, dynamic>{
            '_id': '0038792',
            '_source': <String, dynamic>{
              'title': 'Sabotagem',
              'screens': <dynamic>[<dynamic>[]],
            },
          },
          <String, dynamic>{
            '_id': '0038610',
            '_source': <String, dynamic>{
              'title': 'Salários',
              'screens': <dynamic>[],
            },
          },
        ],
      },
    };

    for (final model in ZxModel.values) {
      settings.zxModel = model;

      final hits = await service.fetchHitsList('s', 30);

      expect(hits.map((hit) => hit.title), <String>[
        'Sabotagem',
        'Salários',
      ], reason: model.name);
      expect(hits.first.iconUrl, isEmpty, reason: model.name);
    }
  });

  test('ZXOKO-BAN uses the reachable ZXInfo media mirror', () async {
    settings.zxModel = ZxModel.zx81;
    final archiveBytes = Uint8List.fromList(<int>[0x50, 0x4b, 1, 2, 3]);
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'api.zxinfo.dk') {
        return http.Response(
          _softwareResponse(
            id: '0044834',
            title: 'ZXOKO-BAN',
            path: '/zxdb/sinclair/entries/0044834/ZXOKO-BAN.p.zip',
          ),
          200,
        );
      }
      return http.Response.bytes(archiveBytes, 200);
    });
    final remoteService = ZxApiService(settings, client: client);

    final software = await remoteService.fetchSoftware('0044834');

    expect(software.tapeFiles, <String>[
      'https://zxinfo.dk/media/zxdb/sinclair/entries/0044834/'
          'ZXOKO-BAN.p.zip',
    ]);
    expect(
      await remoteService.downloadTape(software.tapeFiles.single),
      orderedEquals(archiveBytes),
    );
    expect(requests, hasLength(2));
    expect(requests.last.url.host, 'zxinfo.dk');
    expect(requests.last.headers['user-agent'], 'ZX Tape Player/1.0');
  });

  test('ZX80 download preserves punctuation and archive bytes', () async {
    settings.zxModel = ZxModel.zx80;
    final archiveBytes = Uint8List.fromList(<int>[0x50, 0x4b, 4, 5, 6]);
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'api.zxinfo.dk') {
        return http.Response(
          _softwareResponse(
            id: '0036264',
            title: 'Complex Maths Addition',
            path:
                '/zxdb/sinclair/entries/0036264/'
                'ComplexMathsAddition(1K).o.zip',
          ),
          200,
        );
      }
      return http.Response.bytes(archiveBytes, 200);
    });
    final remoteService = ZxApiService(settings, client: client);

    final software = await remoteService.fetchSoftware('0036264');
    final downloaded = await remoteService.downloadTape(
      software.tapeFiles.single,
    );

    expect(downloaded, orderedEquals(archiveBytes));
    expect(
      requests.last.url.pathSegments.last,
      'ComplexMathsAddition(1K).o.zip',
    );
    expect(requests.last.url.host, 'zxinfo.dk');
  });

  test('accepts explicit TZX releases for ZX81 and ZX80', () async {
    const path =
        '/zxdb/sinclair/entries/0031849/Trader(Trimp).tzx.zip';
    const expectedUrl =
        'https://zxinfo.dk/media/zxdb/sinclair/entries/0031849/'
        'Trader(Trimp).tzx.zip';

    for (final model in <ZxModel>[ZxModel.zx81, ZxModel.zx80]) {
      settings.zxModel = model;
      final client = MockClient(
        (_) async => http.Response(
          _softwareResponse(id: '0031849', title: 'Trader', path: path),
          200,
        ),
      );
      final remoteService = ZxApiService(settings, client: client);

      final software = await remoteService.fetchSoftware('0031849');

      expect(software.tapeFiles, <String>[expectedUrl], reason: model.name);
    }
  });

  test('accepts generic ZIP names in ZX81 and ZX80 directories', () async {
    const archiveBase =
        'https://archive.org/download/World_of_Spectrum_June_2017_Mirror/'
        'World%20of%20Spectrum%20June%202017%20Mirror.zip/'
        'World%20of%20Spectrum%20June%202017%20Mirror';
    final cases =
        <({ZxModel model, List<String> paths, String incompatiblePath})>[
          (
            model: ZxModel.zx81,
            paths: <String>[
              '/pub/sinclair/zx81/games/s/SCRMBL81.ZIP',
              '/pub/sinclair/zx81/games/s/Scram_81.ZIP',
            ],
            incompatiblePath: '/pub/sinclair/zx81/games/s/not-zx81.tap.zip',
          ),
          (
            model: ZxModel.zx80,
            paths: <String>['/pub/sinclair/zx80/games/s/GENERIC.ZIP'],
            incompatiblePath: '/pub/sinclair/zx80/games/s/not-zx80.p.zip',
          ),
        ];

    for (final testCase in cases) {
      settings.zxModel = testCase.model;
      final client = MockClient(
        (_) async => http.Response(
          _softwareResponseForPaths(
            id: '0029273',
            title: 'Generic archive',
            paths: <String>[...testCase.paths, testCase.incompatiblePath],
          ),
          200,
        ),
      );
      final remoteService = ZxApiService(settings, client: client);

      final software = await remoteService.fetchSoftware('0029273');

      expect(
        software.tapeFiles,
        testCase.paths
            .map((path) => '$archiveBase${path.substring('/pub'.length)}')
            .toList(),
        reason: testCase.model.name,
      );
    }
  });
}

String _softwareResponse({
  required String id,
  required String title,
  required String path,
}) {
  return _softwareResponseForPaths(id: id, title: title, paths: <String>[path]);
}

String _softwareResponseForPaths({
  required String id,
  required String title,
  required List<String> paths,
}) {
  return json.encode(<String, dynamic>{
    '_id': id,
    '_source': <String, dynamic>{
      'title': title,
      'releases': <dynamic>[
        <String, dynamic>{
          'files': paths
              .map((path) => <String, dynamic>{'path': path})
              .toList(),
        },
      ],
    },
  });
}

class _RecordingApiBaseHelper extends ApiBaseHelper {
  _RecordingApiBaseHelper() : super('', '');

  final List<String> urls = <String>[];
  String? failOnceForPrefix;
  dynamic response = <String, dynamic>{
    'hits': <String, dynamic>{'hits': <dynamic>[]},
  };

  @override
  Future<dynamic> get(String url) async {
    urls.add(url);
    if (failOnceForPrefix != null && url.startsWith(failOnceForPrefix!)) {
      failOnceForPrefix = null;
      throw Exception('Simulated endpoint failure');
    }
    if (url.startsWith('/suggest/')) return <dynamic>[];
    return response;
  }
}

class _FakeSettingsService implements SettingsService {
  @override
  AudioFilterType audioFilter = SettingsService.defaultAudioFilter;

  @override
  ZxModel zxModel = SettingsService.defaultZxModel;

  @override
  Stream<AudioFilterType> get filterChanges =>
      const Stream<AudioFilterType>.empty();

  @override
  Future<void> load() async {}

  @override
  Future<void> resetAudioFilterToDefault() async {
    audioFilter = SettingsService.defaultAudioFilter;
  }

  @override
  Future<void> resetZxModelToDefault() async {
    zxModel = SettingsService.defaultZxModel;
  }

  @override
  Future<void> setAudioFilter(AudioFilterType filter) async {
    audioFilter = filter;
  }

  @override
  Future<void> setZxModel(ZxModel model) async {
    zxModel = model;
  }
}
