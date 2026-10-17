import 'package:html/parser.dart' as html;

import '../catalog_client.dart';
import '../models.dart';
import 'store_source.dart';

const devStoreBase = 'https://xboxdevstore.github.io/';

class DevStoreSource extends StoreSource {
  const DevStoreSource({this.base = devStoreBase});

  final String base;

  @override
  String get id => 'devstore';

  @override
  String get name => 'Xbox Dev Store';

  @override
  int get priority => 1;

  @override
  Future<CatalogLoad> load(FetchText fetch) async {
    final page = Uri.parse(base);
    return CatalogLoad(parseDevStorePage(await fetch(page), page), const []);
  }
}

List<CatalogApp> parseDevStorePage(String source, Uri page) {
  final doc = html.parse(source);
  final out = <CatalogApp>[];
  final used = <String>{};
  for (final card in doc.querySelectorAll('div.card')) {
    final title = card.querySelector('.card-title')?.text.trim();
    if (title == null || title.isEmpty) continue;

    String? download;
    var official = '';
    for (final a in card.querySelectorAll('a[href]')) {
      final href = a.attributes['href']!;
      final label = a.text.trim().toLowerCase();
      if (label.contains('download')) {
        download ??= href;
      } else if (label.contains('official') || label.contains('page')) {
        official = href;
      }
    }
    if (download == null && official.contains('emulationrevival')) continue;

    var slug = slugify(title);
    if (!used.add(slug)) slug = '$slug-${used.length}';
    final img = card.querySelector('img.card-img-top')?.attributes['src'];
    final version = download == null ? null : versionFromUrl(download);
    final description = card.querySelector('.card-text')?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

    out.add(CatalogApp(
      slug: slug,
      base: page,
      name: title,
      summary: description,
      versionText: version ?? '',
      version: parseLooseVersion(version),
      updated: '',
      developer: '',
      category: 'App',
      compatibility: const [],
      cover: img == null ? null : page.resolve(img).toString(),
      about: '',
      aboutText: description,
      downloads: classifyDownloads(download == null ? const [] : [CatalogDownload(label: 'Download App', url: download)], variants: true),
      source: official,
      package: null,
      sourceId: 'devstore',
      sourceName: 'Xbox Dev Store',
    ));
  }
  return out;
}
