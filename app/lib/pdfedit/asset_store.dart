/// Persistent, file-backed library of reusable PNGs (saved signatures, custom
/// stamps). Lives in the user's app-data folder so signatures created once
/// are offered again in every later session.
library;

import 'dart:io';
import 'dart:typed_data';

class StoredAsset {
  final File file;
  final Uint8List bytes;
  const StoredAsset(this.file, this.bytes);
  String get name => file.uri.pathSegments.last;
}

class AssetStore {
  AssetStore(this.dir);

  /// Default location: `%APPDATA%\stockcalc\<kind>` (or the home folder).
  factory AssetStore.forKind(String kind) {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return AssetStore(Directory('$base${Platform.pathSeparator}stockcalc${Platform.pathSeparator}$kind'));
  }

  final Directory dir;

  /// Newest first.
  Future<List<StoredAsset>> list() async {
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.png')) files.add(e);
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return [for (final f in files) StoredAsset(f, await f.readAsBytes())];
  }

  Future<StoredAsset> add(Uint8List png) async {
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.png');
    await f.writeAsBytes(png, flush: true);
    return StoredAsset(f, png);
  }

  Future<void> delete(StoredAsset asset) async {
    if (await asset.file.exists()) await asset.file.delete();
  }
}
