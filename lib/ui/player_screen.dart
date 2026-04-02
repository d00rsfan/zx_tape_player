import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:marquee_widget/marquee_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/models/args/player_args.dart';
import 'package:zx_tape_player/models/software_model.dart';
import 'package:zx_tape_player/services/backend_service.dart';
import 'package:zx_tape_player/services/responses/api_response.dart';
import 'package:zx_tape_player/ui/widgets/app_error.dart';
import 'package:zx_tape_player/ui/widgets/cassette.dart';
import 'package:zx_tape_player/ui/widgets/loading_progress.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/tape_player.dart';
import 'package:zx_tape_player/utils/extensions.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  static const routeName = '/player';

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class Choice {
  const Choice({required this.title, required this.icon, this.pressed});

  final String title;
  final IconData icon;
  final Function? pressed;
}

class _PlayerScreenState extends State<PlayerScreen> {
  _PlayerScreenBloc? _bloc;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _bloc?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bloc == null) {
      var args = ModalRoute.of(context)!.settings.arguments;
      _bloc = _PlayerScreenBloc(args as PlayerArgs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ApiResponse<SoftwareModel>>(
        stream: _bloc!.softwareStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            switch (snapshot.data!.status) {
              case Status.LOADING:
                return Scaffold(
                    body: LoadingProgress(
                  loadingText: tr("loading"),
                ));
              case Status.COMPLETED:
                return _buildScreen(context, snapshot.data!);
              case Status.ERROR:
                return Scaffold(
                    body: AppError(
                  text: tr('data_retrieving_error'),
                  buttonText: tr('retry'),
                  action: () => _bloc!.refresh(),
                ));
            }
          }
          return const SizedBox.shrink();
        });
  }

  Widget _buildScreen(
      BuildContext context, ApiResponse<SoftwareModel> response) {
    var model = response.data!;

    List<Choice> choices = <Choice>[
      Choice(title: tr('open_tape_web'), icon: Icons.open_in_new_rounded),
      Choice(title: tr('share_tape'), icon: Icons.share_rounded)
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_outlined,
            color: Colors.white,
            size: 16,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actionsIconTheme:
            const IconThemeData(size: 30.0, color: Colors.white, opacity: 10.0),
        actions: [
          (!model.isRemote)
              ? const SizedBox.shrink()
              : PopupMenuButton<Choice>(
                  color: HexColor('#3B4E63'),
                  onSelected: (value) async {
                    if (value.title == tr('open_tape_web')) {
                      await _bloc!.openExternalUrl(model.id!);
                    } else if (value.title == tr('share_tape')) {
                      await _bloc!.shareExternalUrl(model);
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return choices.map((Choice choice) {
                      return PopupMenuItem<Choice>(
                        value: choice,
                        child: Row(
                          children: <Widget>[
                            Icon(
                              choice.icon,
                              size: 16.0,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 16.0),
                            Text(choice.title,
                                style: const TextStyle(
                                    letterSpacing: -0.5, color: Colors.white)),
                          ],
                        ),
                      );
                    }).toList();
                  },
                ),
        ],
        title: Marquee(
          child: Text(model.title,
              style:
                  const TextStyle(color: Colors.white, letterSpacing: 0.1)),
        ),
        titleSpacing: 0.0,
        toolbarHeight: 60.0,
        backgroundColor: HexColor('#28384C'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _buildInfoWidget(context, response),
            model.tapeFiles.isNotEmpty
                ? TapePlayer(software: model)
                : Container(
                    color: HexColor('#3B4E63'),
                    height: 50.0,
                    child: Center(
                      child: Text(
                        tr('no_tapes'),
                        style: TextStyle(
                            fontSize: 14,
                            color: HexColor('#AFB6BB'),
                            letterSpacing: -0.5),
                      ),
                    ))
          ],
        ),
      ),
    );
  }
}

Widget _buildInfoWidget(
    BuildContext context, ApiResponse<SoftwareModel> response) {
  var model = response.data!;
  return Expanded(
      child: Container(
          color: HexColor('#172434'),
          child: !model.isRemote
              ? const Center(
                  child: Cassette(animated: false),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 24.0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (context) {
                          var result = model.year ?? '';
                          if (model.genre != null) {
                            if (result.isNotEmpty) result += ' \u2022 ';
                            result += model.genre!;
                          }
                          return Text(
                            result,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: HexColor('#B1B8C1'),
                                letterSpacing: 0.3,
                                fontSize: 12.0),
                          );
                        }),
                        const SizedBox(height: 14.0),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.thumb_up_rounded,
                              color: HexColor('#B1B8C1'),
                              size: 12.0,
                            ),
                            const SizedBox(width: 5.0),
                            Text(
                              model.votes?.toString() ?? tr('na'),
                              style: TextStyle(
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                  fontSize: 12.0),
                            ),
                            const SizedBox(width: 20),
                            Icon(
                              Icons.star_rounded,
                              color: HexColor('#B1B8C1'),
                              size: 14.0,
                            ),
                            const SizedBox(width: 5.0),
                            Text(
                              model.score != null && model.score! > 0
                                  ? model.score.toString()
                                  : tr('na'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                  fontSize: 12.0),
                            ),
                            const SizedBox(width: 20),
                            Icon(
                              Icons.account_balance_wallet_rounded,
                              color: HexColor('#B1B8C1'),
                              size: 12.0,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              model.price.isNullOrEmpty()
                                  ? tr('na')
                                  : model.price!,
                              style: const TextStyle(
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                  fontSize: 12.0),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        model.remarks.isNullOrEmpty()
                            ? const SizedBox.shrink()
                            : const SizedBox(height: 24.0),
                        model.remarks.isNullOrEmpty()
                            ? const SizedBox.shrink()
                            : Row(children: [
                                Expanded(
                                    child: Text(
                                  model.remarks!.removeAllHtmlTags(),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                      height: 1.4,
                                      fontSize: 14.0),
                                  maxLines: 256,
                                ))
                              ]),
                        model.authors.isNotEmpty
                            ? const SizedBox(height: 24.0)
                            : const SizedBox.shrink(),
                        model.authors.isNotEmpty
                            ? Row(children: [
                                Expanded(
                                  child: Text(
                                    model.authors
                                        .map((a) =>
                                            '\u00B7 ${a.name} - ${a.role}')
                                        .join('\r\n'),
                                    style: TextStyle(
                                        color: HexColor('#B1B8C1'),
                                        letterSpacing: 0.3,
                                        height: 1.6,
                                        fontSize: 12.0),
                                    overflow: TextOverflow.clip,
                                  ),
                                )
                              ])
                            : const SizedBox.shrink(),
                        const SizedBox(height: 24.0),
                        Column(
                            children: model.screenShotUrls
                                .map(
                                  (e) => Center(
                                      child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              0, 0, 0, 24),
                                          child: Column(children: [
                                            CachedNetworkImage(
                                              imageUrl: e.url,
                                              imageBuilder:
                                                  (context, provider) {
                                                return Image(image: provider);
                                              },
                                            ),
                                            const SizedBox(height: 8.0),
                                            Text(
                                              e.type,
                                              style: TextStyle(
                                                  color: HexColor('#B1B8C1'),
                                                  letterSpacing: 0.3,
                                                  fontSize: 12.0),
                                            )
                                          ]))),
                                )
                                .toList())
                      ]))));
}

class _PlayerScreenBloc {
  final PlayerArgs args;

  final _backendService = getIt<BackendService>();
  final StreamController<ApiResponse<SoftwareModel>> _softwareController =
      StreamController<ApiResponse<SoftwareModel>>();

  StreamSink<ApiResponse<SoftwareModel>> get softwareSink =>
      _softwareController.sink;

  Stream<ApiResponse<SoftwareModel>> get softwareStream =>
      _softwareController.stream;

  _PlayerScreenBloc(this.args) {
    _fetchData(args);
  }

  Future openExternalUrl(String id) async {
    var urlString = await _backendService.getExternalUrl(id);
    var url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      throw 'Could not launch $urlString';
    }
  }

  Future shareExternalUrl(SoftwareModel model) async {
    var url = await _backendService.getExternalUrl(model.id!);
    await SharePlus.instance.share(ShareParams(text: url, title: model.title));
  }

  Future refresh() async {
    await _fetchData(args);
  }

  Future _fetchData(PlayerArgs args) async {
    softwareSink.add(ApiResponse.loading(''));
    try {
      SoftwareModel model;
      if (args.isRemote) {
        model = await _backendService.fetchSoftware(args.id);
      } else {
        model = await _backendService.recognizeTape(args.id,
            localTitle: tr('local_file'));
      }
      softwareSink.add(ApiResponse.completed(model));
    } catch (e) {
      softwareSink.add(ApiResponse.error(e.toString()));
    }
  }

  Future _requestReview() async {
    const key = 'lastReviewDate';
    var prefs = await SharedPreferences.getInstance();
    var millisecondsSinceEpoch = prefs.getInt(key);
    var reviewNeeded = false;
    if (millisecondsSinceEpoch == null) {
      reviewNeeded = true;
    } else {
      var lastReviewDate =
          DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
      if (DateTime.now().difference(lastReviewDate).inDays > 60) {
        reviewNeeded = true;
      }
    }
    if (reviewNeeded) {
      final inAppReview = InAppReview.instance;
      var isAvailable = await inAppReview.isAvailable();
      if (isAvailable) await inAppReview.requestReview();
      prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    }
  }

  void dispose() {
    _requestReview();
    _softwareController.close();
  }
}
