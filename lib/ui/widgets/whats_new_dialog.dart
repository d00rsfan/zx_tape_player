import 'package:easy_localization/easy_localization.dart';
// flutter_markdown_plus still accepts the Flutter SDK Material theme.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy show Theme;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zx_tape_player/main.dart';
import 'package:zx_tape_player/services/whats_new_service.dart';

bool _dialogOpen = false;

Future<void> showWhatsNewDialog(
  BuildContext context, {
  bool automatic = false,
}) async {
  if (_dialogOpen) return;
  _dialogOpen = true;
  try {
    final service = getIt<WhatsNewService>();
    await service.load();
    if (automatic && service.shouldShowHeadphoneWarning) {
      if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
      FocusManager.instance.primaryFocus?.unfocus();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('headphone_warning_dialog'),
          scrollable: true,
          backgroundColor: const Color(0xff172434),
          titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
          contentTextStyle: const TextStyle(
            fontFamily: 'Roboto',
            color: Color(0xffe7eced),
            fontSize: 16,
            height: 1.45,
          ),
          title: Text(tr('headphone_warning_title')),
          content: Text(tr('headphone_warning_body')),
          actions: [
            TextButton(
              key: const ValueKey('headphone_warning_close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(tr('headphone_warning_ack')),
            ),
          ],
        ),
      );
      await service.markHeadphoneWarningSeen();
    }
    if (automatic && !service.shouldShowAutomatically) return;
    if (!context.mounted) return;
    final document = await DefaultAssetBundle.of(context)
        .loadString('CHANGELOG.md');
    // The dialog already has its own localized title.
    final changelog = document.replaceFirst(
      RegExp(r'^# Changelog[ \t]*\r?\n\s*'),
      '',
    );
    if (changelog.trim().isEmpty) {
      throw StateError('The bundled changelog is empty');
    }
    // A slow startup must not open a notice over a screen the user navigated to.
    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await showDialog<void>(
      context: context,
      requestFocus: true,
      builder: (_) => WhatsNewDialog(service: service, changelog: changelog),
    );
  } catch (error) {
    debugPrint('Could not show an app notice: $error');
    if (!automatic && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('whats_new_load_error'))));
    }
  } finally {
    _dialogOpen = false;
  }
}

class WhatsNewDialog extends StatefulWidget {
  const WhatsNewDialog({
    super.key,
    required this.service,
    required this.changelog,
  });

  final WhatsNewService service;
  final String changelog;

  @override
  State<WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends State<WhatsNewDialog> {
  final _scrollController = ScrollController();
  bool _saving = false;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await widget.service.markShown();
      } catch (_) {
        if (mounted) setState(() => _errorKey = 'whats_new_save_error');
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _setNeverShowAgain(bool? value) async {
    if (value == null || _saving) return;
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await widget.service.setNeverShowAgain(value);
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'whats_new_save_error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openLink(String text, String? href, String title) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Keep the release notes open if no browser can handle the link.
    }
    if (mounted) setState(() => _errorKey = 'whats_new_link_error');
  }

  @override
  Widget build(BuildContext context) {
    final bodyTheme = legacy.Theme.of(context).copyWith(
      brightness: Brightness.dark,
      textTheme: legacy.Theme.of(context).textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: const Color(0xffe7eced),
        displayColor: Colors.white,
      ),
    );
    final markdownStyle = MarkdownStyleSheet.fromTheme(bodyTheme).copyWith(
      p: bodyTheme.textTheme.bodyMedium!.copyWith(fontSize: 15, height: 1.5),
      h1: bodyTheme.textTheme.headlineSmall,
      h2: bodyTheme.textTheme.titleLarge!.copyWith(
        fontSize: 18,
        color: const Color(0xffb8dcff),
      ),
      h2Padding: const EdgeInsets.only(top: 16, bottom: 8),
      h3: bodyTheme.textTheme.titleMedium!.copyWith(
        fontWeight: FontWeight.bold,
      ),
      h3Padding: const EdgeInsets.only(top: 8),
      a: const TextStyle(
        color: Color(0xffa9d8ff),
        decoration: TextDecoration.underline,
      ),
      code: const TextStyle(
        fontFamily: 'monospace',
        color: Color(0xffe7eced),
        backgroundColor: Color(0xff28384c),
      ),
    );

    return PopScope(
      canPop: !_saving,
      child: Dialog(
        key: const ValueKey('whats_new_dialog'),
        backgroundColor: const Color(0xff172434),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  tr('whats_new_title'),
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xff546b7f)),
            Expanded(
              child: ScrollbarTheme(
                data: const ScrollbarThemeData(
                  thumbColor: WidgetStatePropertyAll(Color(0xffafb6bb)),
                  thickness: WidgetStatePropertyAll(5),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  child: Markdown(
                    key: const ValueKey('whats_new_changelog'),
                    controller: _scrollController,
                    data: widget.changelog,
                    padding: const EdgeInsets.all(20),
                    styleSheet: markdownStyle,
                    onTapLink: _openLink,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xff546b7f)),
            CheckboxListTile(
              key: const ValueKey('whats_new_never_show_again'),
              value: widget.service.neverShowAgain,
              onChanged: _saving ? null : _setNeverShowAgain,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                tr('whats_new_never_show_again'),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            if (_errorKey != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  tr(_errorKey!),
                  style: const TextStyle(
                    color: Color(0xffffb4ab),
                    fontSize: 12,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const ValueKey('whats_new_close'),
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(tr('whats_new_close')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
