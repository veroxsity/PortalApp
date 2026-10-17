import '../catalog_client.dart';

typedef FetchText = Future<String> Function(Uri uri);

abstract class StoreSource {
  const StoreSource();

  String get id;
  String get name;

  int get priority;

  Future<CatalogLoad> load(FetchText fetch);
}

String slugify(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

final _versionPattern = RegExp(r'(?<![\d.])v?(\d+(?:\.\d+){1,3})(?![\d])');

String? versionFromText(String text) {
  for (final part in Uri.decodeFull(text).split('/').reversed) {
    final v = _versionPattern.firstMatch(part)?.group(1);
    if (v != null) return v;
  }
  return null;
}

String? versionFromUrl(String url) {
  final release = RegExp(r'/releases/download/([^/]+)/').firstMatch(url)?.group(1);
  return (release == null ? null : versionFromText(release)) ?? versionFromText(url.split('?').first);
}
