import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zx_tape_player/models/args/player_args.dart';
import 'package:zx_tape_player/services/tape_conversion_service.dart';
import 'package:zx_tape_player/ui/player_screen.dart';
import 'package:zx_tape_player/ui/search_screen.dart';
import 'package:zx_tape_player/ui/settings_screen.dart';
import 'package:zx_tape_player/ui/tips_screen.dart';
import 'package:zx_tape_player/utils/bar_helper.dart';
import 'package:zx_tape_player/utils/definitions.dart';
import 'package:zx_tape_player/utils/extensions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  static const routeName = '/home';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ExtractedTape {
  final String name;
  final List<int> bytes;
  _ExtractedTape(this.name, this.bytes);
}

enum _HomeMenuAction { settings, tips }

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();

  static _ExtractedTape? _extractTapeFromZip(List<int> zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      if (file.isFile) {
        var ext = p.extension(file.name).replaceAll('.', '').toLowerCase();
        if (Definitions.supportedTapeExtensions.contains(ext)) {
          return _ExtractedTape(p.basename(file.name), file.content as List<int>);
        }
      }
    }
    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: 60.0,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          actions: [
            PopupMenuButton<_HomeMenuAction>(
              key: const ValueKey('home_menu_button'),
              color: HexColor('#3B4E63'),
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onSelected: (action) {
                if (action == _HomeMenuAction.settings) {
                  Navigator.of(context).pushNamed(SettingsScreen.routeName);
                } else {
                  Navigator.of(context).pushNamed(TipsScreen.routeName);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _HomeMenuAction.settings,
                  child: Row(children: [
                    const Icon(Icons.settings_rounded,
                        size: 16.0, color: Colors.white),
                    const SizedBox(width: 16.0),
                    Text(tr('settings_menu_item'),
                        style: const TextStyle(
                            letterSpacing: -0.5, color: Colors.white)),
                  ]),
                ),
                PopupMenuItem(
                  value: _HomeMenuAction.tips,
                  child: Row(children: [
                    const Icon(Icons.lightbulb_outline_rounded,
                        size: 16.0, color: Colors.white),
                    const SizedBox(width: 16.0),
                    Text(tr('tips_menu_item'),
                        style: const TextStyle(
                            letterSpacing: -0.5, color: Colors.white)),
                  ]),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: Container(
                padding: const EdgeInsets.fromLTRB(16.0, 40.0, 16.0, 0),
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
                  const SizedBox(height: 12.0),
                  Text(tr('search_publisher_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.0,
                          height: 1.4,
                          color: HexColor('#546B7F'),
                          letterSpacing: -0.5)),
                  const SizedBox(height: 53.0),
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
                      FilePicker.clearTemporaryFiles();
                      final selection =
                          await FilePicker.pickFile(type: FileType.any);
                      if (selection != null) {
                        var filePath = selection.path!;
                        var file = File(filePath);
                        var bytes = await file.readAsBytes();

                        if (p.extension(filePath).toLowerCase() == '.zip') {
                          var extracted = _extractTapeFromZip(bytes);
                          if (extracted != null) {
                            var tempDir = await getTemporaryDirectory();
                            var tapePath =
                                '${tempDir.path}/tapes/${extracted.name}';
                            await Directory(p.dirname(tapePath))
                                .create(recursive: true);
                            await File(tapePath)
                                .writeAsBytes(extracted.bytes);
                            filePath = tapePath;
                            bytes = Uint8List.fromList(extracted.bytes);
                          }
                        }

                        final supported = await isTapeImageSupported(
                            bytes, p.basename(filePath));
                        if (supported) {
                          if (mounted) {
                            Navigator.pushNamed(
                                context, PlayerScreen.routeName,
                                arguments: PlayerArgs(filePath,
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
                ])))));
  }
}
