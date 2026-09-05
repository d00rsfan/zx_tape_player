import 'package:flutter/services.dart';
import 'package:zx_tape_player/snapshots/snapshot_receiver_manifest.dart';

/// Loads receiver assets on the root isolate. The returned byte-only bundle is
/// safe to pass to the conversion worker; the worker never accesses rootBundle.
class SnapshotAssetLoader {
  const SnapshotAssetLoader({this.bundle});

  final AssetBundle? bundle;

  Future<SnapshotAssetBundle> load() async {
    final source = bundle ?? rootBundle;
    final assets = SnapshotAssetBundle(
      receiver48Tap: await _load(
        source,
        SnapshotReceiverManifest.receiver48.assetPath,
      ),
      receiver128Tap: await _load(
        source,
        SnapshotReceiverManifest.receiver128.assetPath,
      ),
      registerBlob: await _load(
        source,
        SnapshotReceiverManifest.registerAssetPath,
      ),
    );
    assets.verify();
    return assets;
  }

  Future<Uint8List> _load(AssetBundle source, String path) async {
    final data = await source.load(path);
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}
