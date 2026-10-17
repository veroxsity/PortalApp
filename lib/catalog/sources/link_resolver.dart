import 'dart:convert';

import '../../portal/models.dart';
import '../models.dart';
import 'store_source.dart';

String? parseMediaFire(String page) {
  final scrambled = RegExp(r'data-scrambled-url="([^"]+)"').firstMatch(page)?.group(1);
  if (scrambled != null) {
    try {
      final url = utf8.decode(base64.decode(scrambled));
      if (url.startsWith('http')) return url;
    } catch (_) {}
  }
  final button = RegExp(r'<a[^>]*id="downloadButton"[^>]*>').firstMatch(page)?.group(0);
  final href = button == null ? null : RegExp(r'href="(https?://[^"]+)"').firstMatch(button)?.group(1);
  if (href != null) return href;
  return RegExp(r'https://download\d*\.mediafire\.com/[^"\s<>]+').firstMatch(page)?.group(0);
}

final _wanted = RegExp(r'\.(msix|appx|msixbundle|appxbundle|zip|7z)$', caseSensitive: false);
final _unwanted = RegExp(r'(?:^|[^a-z])(arm64|arm|x86|win32|linux|mac|android|source|src|symbols|pdb|debug)(?:[^a-z]|$)', caseSensitive: false);

List<CatalogDownload> pickGithubAssets(String json) {
  final release = jsonDecode(json);
  if (release is! Map) return const [];
  final all = <(String, CatalogDownload)>[];
  for (final a in (release['assets'] as List? ?? const [])) {
    if (a is! Map) continue;
    final name = a['name'] as String? ?? '';
    final url = a['browser_download_url'] as String?;
    if (url == null || url.contains('/archive/') || !_wanted.hasMatch(name)) continue;
    final size = a['size'] as num?;
    all.add((
      name,
      CatalogDownload(
        label: name,
        url: url,
        size: size == null ? null : '${(size / (1024 * 1024)).toStringAsFixed(size < 10 * 1024 * 1024 ? 1 : 0)} MB',
      ),
    ));
  }
  final fit = [for (final (name, d) in all) if (!_unwanted.hasMatch(name)) d];
  return fit.isEmpty ? [for (final (_, d) in all) d] : fit;
}

class LinkResolver {
  const LinkResolver(this.fetch);

  final FetchText fetch;

  Future<CatalogApp> resolve(CatalogApp app) async {
    final found = <CatalogDownload>[];

    for (final link in app.links) {
      if (isMediaFire(link.url)) {
        final direct = parseMediaFire(await fetch(Uri.parse(link.url!)));
        if (direct == null) throw PortalException('MediaFire did not give a download for ${app.name}. Open the link in a browser instead.');
        found.add(CatalogDownload(label: link.label, url: direct));
      } else if (isGithubRelease(link.url)) {
        found.addAll(await _release(githubRepo(link.url!)));
      }
    }
    if (found.isEmpty) found.addAll(await _release(githubRepo(app.source)));
    if (found.isEmpty) throw PortalException('There is no download for ${app.name} that can be installed from here.');

    return app.copyWith(downloads: [...classifyDownloads(found, variants: true), ...app.downloads.where((d) => d.role == DownloadRole.link && !isMediaFire(d.url) && !isGithubRelease(d.url))]);
  }

  Future<List<CatalogDownload>> _release(String? repo) async {
    if (repo == null) return const [];
    try {
      return pickGithubAssets(await fetch(Uri.parse('https://api.github.com/repos/$repo/releases/latest')));
    } on PortalException catch (e) {
      if (e.status == 403 || e.status == 429) {
        throw PortalException('GitHub is limiting requests from this network right now. Try again in a few minutes.');
      }
      if (e.status == 404) return const [];
      rethrow;
    }
  }
}
