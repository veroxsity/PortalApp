import '../models.dart';


String normalizeName(String s) {
  var n = s.toLowerCase().replaceAll(RegExp(r'\b(uwp|xbox|for xbox|port|app|emulator)\b'), ' ');
  n = n.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return n;
}

Set<String> repoKeys(CatalogApp a) => {
      for (final u in [a.source, for (final d in a.downloads) d.url ?? ''])
        if (githubRepo(u) != null) githubRepo(u)!,
    };

bool _same(CatalogApp a, CatalogApp b) {
  if (a.sourceId == b.sourceId) return false;
  if (repoKeys(a).intersection(repoKeys(b)).isNotEmpty) return true;
  final na = normalizeName(a.name);
  return na.isNotEmpty && na == normalizeName(b.name);
}

List<CatalogApp> mergeApps(List<List<CatalogApp>> perStore) {
  final merged = <CatalogApp>[];
  final extras = <int, List<CatalogApp>>{};
  for (final store in perStore) {
    final joined = <int>{};
    for (final app in store) {
      var target = -1;
      for (var i = 0; i < merged.length; i++) {
        if (joined.contains(i)) continue;
        if (_same(merged[i], app) && (extras[i] ?? const []).every((e) => e.sourceId != app.sourceId)) {
          target = i;
          break;
        }
      }
      if (target < 0) {
        merged.add(app);
      } else {
        joined.add(target);
        (extras[target] ??= []).add(app);
      }
    }
  }
  return [for (var i = 0; i < merged.length; i++) _combine(merged[i], extras[i] ?? const [])];
}

CatalogApp _combine(CatalogApp primary, List<CatalogApp> others) {
  if (others.isEmpty) return primary;
  final all = [primary, ...others];
  String pick(String Function(CatalogApp) f) => all.map(f).firstWhere((s) => s.isNotEmpty, orElse: () => '');

  CatalogApp? newest;
  for (final a in all) {
    if (a.version == null) continue;
    if (newest == null || a.version!.compareTo(newest.version!) > 0) newest = a;
  }
  final installable = all.where((a) => a.hasFiles).firstOrNull ?? all.where((a) => a.installable).firstOrNull;
  final lead = installable ?? primary;
  final coverOwner = all.where((a) => a.cover != null).firstOrNull;

  return CatalogApp(
    slug: primary.slug,
    base: primary.base,
    name: primary.name,
    summary: pick((a) => a.summary),
    versionText: newest?.versionText ?? primary.versionText,
    version: newest?.version ?? primary.version,
    updated: pick((a) => a.updated),
    developer: pick((a) => a.developer),
    category: primary.category,
    compatibility: primary.compatibility.isNotEmpty ? primary.compatibility : all.expand((a) => a.compatibility).toSet().toList(),
    cover: coverOwner?.cover,
    about: primary.about,
    downloads: lead.downloads,
    source: pick((a) => a.source),
    package: all.map((a) => a.package).whereType<String>().firstOrNull,
    aboutText: primary.aboutText,
    sourceId: lead.sourceId,
    sourceName: all.map((a) => a.sourceName).toSet().join(' + '),
    alsoFrom: [for (final a in all) if (!identical(a, lead)) a],
    origins: all,
  );
}
