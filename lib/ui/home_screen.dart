import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zx_tape_player/models/args/player_args.dart';
import 'package:zx_tape_player/ui/player_screen.dart';
import 'package:zx_tape_player/ui/search_screen.dart';
import 'package:zx_tape_player/utils/bar_helper.dart';
import 'package:zx_tape_player/utils/definitions.dart';
import 'package:zx_tape_player/utils/extensions.dart';
import 'package:zx_tape_to_wav/zx_tape_to_wav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  static const routeName = '/home';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.bottom, SystemUiOverlay.top]);
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: Container(
                padding: const EdgeInsets.fromLTRB(16.0, 100.0, 16.0, 0),
                child: Column(children: <Widget>[
                  Text(tr('find_tape'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16.0,
                          color: Theme.of(context).primaryColor)),
                  const SizedBox(height: 24.0),
                  TextField(
                    controller: _controller,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18.0,
                      letterSpacing: -0.5,
                    ),
                    autofocus: true,
                    onChanged: (text) {
                      if (text.isNotEmpty) {
                        Navigator.pushNamed(context, SearchScreen.routeName,
                            arguments: text);
                        _controller.text = '';
                      }
                    },
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: tr('search_hint'),
                      filled: true,
                      fillColor: HexColor('#28384C'),
                      isDense: true,
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      prefixIcon: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Image.asset(
                              'assets/images/home/search-icon.png')),
                      hintStyle: TextStyle(
                        fontSize: 12.0,
                        color: HexColor('546B7F'),
                        letterSpacing: -0.5,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 16.0),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: const BorderSide(
                            color: Colors.transparent, width: 0.0),
                        borderRadius: BorderRadius.circular(3.5),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: const BorderSide(
                            color: Colors.transparent, width: 0.0),
                        borderRadius: BorderRadius.circular(3.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 65.0),
                  Text(tr('select_file'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16.0,
                          color: Theme.of(context).primaryColor)),
                  const SizedBox(height: 24.0),
                  TextButton(
                    child: Text(
                      tr('select_from_files'),
                      style: const TextStyle(fontSize: 14.0),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                      backgroundColor: HexColor('#68B8DF'),
                      padding:
                          const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 16.0),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(2.0)),
                      ),
                    ),
                    onPressed: () async {
                      FilePicker.platform.clearTemporaryFiles();
                      final result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          allowMultiple: false);
                      if (result != null) {
                        PlatformFile selection = result.files.first;
                        var file = File(selection.path!);
                        var tape =
                            await ZxTape.create(await file.readAsBytes());
                        if (tape.tapeType != TapeType.unknown) {
                          if (mounted) {
                            Navigator.pushNamed(
                                context, PlayerScreen.routeName,
                                arguments: PlayerArgs(selection.path!,
                                    isRemote: false));
                          }
                        } else {
                          var message = tr('invalid_file_format').format([
                            Definitions.supportedTapeExtensions
                                .map((e) => '.${e.toUpperCase()}')
                                .join(', ')
                          ]);
                          if (mounted) {
                            BarHelper.showSnackBar(
                                message: message,
                                barType: SnackBarType.error,
                                context: context);
                          }
                        }
                      }
                    },
                  ),
                ]))));
  }
}
