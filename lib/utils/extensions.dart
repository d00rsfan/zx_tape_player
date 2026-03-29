import 'dart:ui';

extension StringFormatExtension on String {
  String format(List<dynamic> arguments) {
    var result = this;
    for (var arg in arguments) {
      result = result.replaceFirst(RegExp(r'%[sd]'), arg.toString());
    }
    return result;
  }
}

extension StringIsNullOrEmptyExtension on String? {
  bool isNullOrEmpty() => this == null || this!.trim().isEmpty;
}

extension RemoveAllHtmlTagsExtension on String {
  String removeAllHtmlTags() {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return replaceAll(exp, '');
  }
}

extension DurationToStringExtension on Duration {
  String toTimeString() {
    return RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
        .firstMatch("$this")
        ?.group(1) ??
        "$this";
  }
}

// ignore: deprecated_member_use
class HexColor extends Color {
  static int _getColorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    return int.parse(hexColor, radix: 16);
  }

  // ignore: deprecated_member_use
  HexColor(final String hexColor) : super(_getColorFromHex(hexColor));
}

extension EncodeStringExtension on String {
  String safeEncode() {
    return Uri.encodeQueryComponent(replaceAll('/', ' '));
  }
}
