import 'package:flutter/material.dart';
import 'package:zx_tape_player/utils/extensions.dart';

enum SnackBarType { info, warning, error }

class BarHelper {
  BarHelper._();

  static Future<void> showSnackBar({
    required String message,
    required BuildContext context,
    SnackBarType barType = SnackBarType.info,
    Duration duration = const Duration(seconds: 3),
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    await Future<void>.delayed(const Duration());
    messenger.removeCurrentSnackBar();
    var backgroundColor = HexColor('#172434');
    if (barType == SnackBarType.warning) backgroundColor = HexColor('#E6A817');
    if (barType == SnackBarType.error) backgroundColor = HexColor('#D9512D');
    final snackBar = SnackBar(
      duration: duration,
      backgroundColor: backgroundColor,
      content: Text(
        message,
        style: const TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    );
    await Future<void>.delayed(const Duration());
    messenger.showSnackBar(snackBar);
  }
}
