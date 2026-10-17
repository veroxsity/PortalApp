import 'dart:convert';
import 'dart:io';

import 'package:portal_app/catalog/models.dart';
import 'package:portal_app/catalog/sources/devstore_source.dart';
import 'package:portal_app/catalog/sources/merge.dart';
import 'package:portal_app/catalog/sources/revival_source.dart';

Future<String> fetch(Uri uri) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.getUrl(uri);
    final resp = await req.close();
    if (resp.statusCode != 200) throw Exception('${resp.statusCode} for $uri');
    return await utf8.decodeStream(resp);
  } finally {
    http.close(force: true);
  }
}

String row(CatalogApp a) {
  final dl = a.downloads.where((d) => d.role != DownloadRole.link).map((d) => d.name).join(', ');
  final links = a.links.length;
  final lk = a.links.map((l) => l.url).join(' ');
  return '${a.name.padRight(34)} ${a.versionText.padRight(14)} ${a.sourceName.padRight(36)} ${dl.isEmpty ? '(no package)' : dl}${links > 0 ? '  [$lk]' : ''}';
}

Future<void> main() async {
  final sources = [const RevivalSource(), const DevStoreSource()];
  final per = <List<CatalogApp>>[];
  for (final s in sources) {
    final r = await s.load(fetch);
    stdout.writeln('${s.name}: ${r.apps.length} apps${r.failed.isEmpty ? '' : ', failed: ${r.failed}'}');
    per.add(r.apps);
  }
  final merged = mergeApps(per);
  stdout.writeln('merged: ${merged.length} apps\n');
  for (final a in merged) {
    stdout.writeln(row(a));
    for (final o in a.alsoFrom) {
      stdout.writeln('    also: ${o.sourceName} ${o.name} ${o.versionText}');
    }
  }
}
