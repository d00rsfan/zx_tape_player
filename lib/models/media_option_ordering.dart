/// Returns whether [option] explicitly names a supported snapshot file.
///
/// Generic ZIP names are deliberately not classified: their inner member is
/// unknown until the archive is downloaded and resolved.
bool isExplicitSnapshotMediaOption(String option) {
  final parsed = Uri.tryParse(option);
  final path = parsed != null && parsed.path.isNotEmpty ? parsed.path : option;
  final lowerPath = path.toLowerCase();
  return const <String>[
    '.z80',
    '.sna',
    '.z80.zip',
    '.sna.zip',
  ].any(lowerPath.endsWith);
}

/// Stably places explicit snapshot options after every other media option.
List<String> orderMediaOptionsForCarousel(Iterable<String> options) {
  final tapes = <String>[];
  final snapshots = <String>[];
  for (final option in options) {
    (isExplicitSnapshotMediaOption(option) ? snapshots : tapes).add(option);
  }
  return List<String>.unmodifiable(<String>[...tapes, ...snapshots]);
}
