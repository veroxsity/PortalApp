import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../catalog_client.dart';
import '../models.dart';
import 'store_source.dart';

const revivalBase = 'https://emulationrevival.github.io/';

const _pages = {
  'apps': 'App',
  'emulators': 'Emulator',
  'experimental-apps': 'Experimental',
  'frontends': 'Frontend',
  'media-apps': 'Media',
  'ports': 'Port',
  'utilities': 'Utility',
};

class RevivalSource extends StoreSource {
  const RevivalSource({this.base = revivalBase});

  final String base;

  @override
  String get id => 'revival';

  @override
  String get name => 'Emulation Revival';

  @override
  int get priority => 0;

  @override
  Future<CatalogLoad> load(FetchText fetch) async {
    final root = Uri.parse(base);
    try {
      final apps = parseRevivalApi(await fetch(root.resolve('api/catalog.json')));
      if (apps.isNotEmpty) return CatalogLoad(apps, const []);
    } catch (_) {}

    final apps = <CatalogApp>[];
    final failed = <String>[];
    final pages = await Future.wait([
      for (final e in _pages.entries)
        () async {
          try {
            final url = root.resolve('xbox-dev-mode/${e.key}.html');
            return parseRevivalPage(await fetch(url), url, e.value);
          } catch (_) {
            failed.add(e.key);
            return <CatalogApp>[];
          }
        }(),
    ]);
    final seen = <String>{};
    for (final page in pages) {
      for (final app in page) {
        if (seen.add(app.slug)) apps.add(app);
      }
    }
    if (apps.isEmpty && failed.length == _pages.length) throw Exception('Emulation Revival could not be reached.');
    return CatalogLoad(apps, failed);
  }
}

List<CatalogApp> parseRevivalPage(String source, Uri page, String category) {
  final doc = html.parse(source);
  final out = <CatalogApp>[];
  for (final card in doc.querySelectorAll('div.card[id]')) {
    final modal = card.querySelector('.card-modal-content');
    final title = card.querySelector('.card-title')?.text.trim();
    if (modal == null || title == null || title.isEmpty) continue;

    final downloads = <CatalogDownload>[
      for (final a in modal.querySelectorAll('a.download-link'))
        if ((a.attributes['href'] ?? '').isNotEmpty)
          CatalogDownload(label: _labelFor(a.attributes['href']!, a.text.trim()), url: page.resolve(a.attributes['href']!).toString()),
    ];

    final img = card.querySelector('img.card-image')?.attributes['src'];
    final shown = modal.querySelector('.app-version .val')?.text.trim();
    final version = (shown != null && shown.isNotEmpty)
        ? shown
        : downloads.map((d) => versionFromUrl(d.url ?? '')).whereType<String>().firstOrNull;
    final description = card.querySelector('.card-description')?.text.trim() ?? '';

    out.add(CatalogApp(
      slug: card.id,
      base: page,
      name: title,
      summary: description,
      versionText: version ?? '',
      version: parseLooseVersion(version),
      updated: modal.querySelector('time.release-date')?.attributes['datetime'] ?? '',
      developer: _infoValue(modal, 'Developer'),
      category: category,
      compatibility: _compatibility(modal),
      cover: img == null ? null : page.resolve(img).toString(),
      about: '',
      aboutText: description,
      downloads: classifyDownloads(downloads, variants: true),
      source: modal.querySelector('a.source-code-link')?.attributes['href'] ?? '',
      package: null,
      sourceId: 'revival',
      sourceName: 'Emulation Revival',
    ));
  }
  return out;
}

String _labelFor(String href, String text) {
  final file = href.split('?').first.split('/').last.toLowerCase();
  return file.endsWith('.zip') || file.endsWith('.7z') ? 'Download archive' : (text.isEmpty ? 'Download' : text);
}

String _infoValue(Element modal, String label) {
  for (final li in modal.querySelectorAll('ul.info-list > li')) {
    final strong = li.querySelector('strong')?.text.trim() ?? '';
    if (strong.toLowerCase().startsWith(label.toLowerCase())) {
      final clone = li.clone(true);
      clone.querySelector('strong')?.remove();
      return clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
  return '';
}

List<String> _compatibility(Element modal) {
  final text = _infoValue(modal, 'Compatibility');
  return text.isEmpty ? const [] : [text];
}

List<CatalogApp> parseRevivalApi(String source) {
  final root = jsonDecode(source);
  if (root is! Map || root['items'] is! List) throw const FormatException('Not a catalogue.');
  final out = <CatalogApp>[];
  for (final item in (root['items'] as List).whereType<Map>()) {
    String? str(String k) {
      final v = item[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final id = str('id');
    final title = str('title');
    if (id == null || title == null) continue;

    final downloads = <CatalogDownload>[
      for (final d in (item['downloads'] as List? ?? const []).whereType<Map>())
        if ((d['url'] as String?)?.isNotEmpty ?? false) CatalogDownload(label: (d['label'] as String?) ?? 'Download', url: d['url'] as String),
    ];
    if (downloads.isEmpty && str('downloadUrl') != null) downloads.add(CatalogDownload(label: 'Download', url: str('downloadUrl')));

    final version = str('version') ?? downloads.map((d) => versionFromUrl(d.url ?? '')).whereType<String>().firstOrNull;
    final people = (item['contributors'] as Map?) ?? const {};
    final names = <String>{
      for (final role in ['developers', 'modAuthors'])
        for (final p in (people[role] as List? ?? const []).whereType<Map>())
          if (p['name'] is String) p['name'] as String,
    };

    out.add(CatalogApp(
      slug: id,
      base: Uri.parse(revivalBase),
      name: title,
      summary: str('description') ?? '',
      versionText: version ?? '',
      version: parseLooseVersion(version),
      updated: str('releaseDate') ?? '',
      developer: names.join(', '),
      category: str('category') ?? 'App',
      compatibility: [if (str('compatibility') != null) str('compatibility')!],
      cover: str('imageUrl'),
      about: '',
      aboutText: _aboutOf(item, str('description') ?? ''),
      downloads: classifyDownloads(downloads, variants: true),
      source: str('sourceCodeUrl') ?? '',
      package: null,
      sourceId: 'revival',
      sourceName: 'Emulation Revival',
    ));
  }
  return out;
}


String _aboutOf(Map item, String description) {
  List<String> list(String k) => [for (final v in (item[k] as List? ?? const [])) if (v is String && v.trim().isNotEmpty) v.trim()];
  final b = StringBuffer(description);
  final needs = list('requirements');
  final features = list('features');
  if (needs.isNotEmpty) b.write('\n\n## You will need\n\n${needs.map((r) => '- $r').join('\n')}');
  if (features.isNotEmpty) b.write('\n\n## Features\n\n${features.map((f) => '- $f').join('\n')}');
  final links = [
    for (final (label, key) in [('Setup guide', 'setupGuideUrl'), ('Tutorial', 'tutorialUrl'), ('Release notes', 'releaseNotesUrl')])
      if (item[key] is String && (item[key] as String).isNotEmpty) '[$label](${item[key]})',
  ];
  if (links.isNotEmpty) b.write('\n\n${links.join('  ·  ')}');
  return b.toString();
}
