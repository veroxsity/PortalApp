import '../portal/models.dart';
import '../portal/package_info.dart';

// what a catalogue download is, decided from its label and file name
enum DownloadRole { package, dependency, checksum, archive, link }

class CatalogDownload {
  const CatalogDownload({
    required this.label,
    this.file,
    this.url,
    this.architecture,
    this.size,
    this.role = DownloadRole.link,
  });

  final String label;

  // a file inside the project folder, or an absolute url, never both
  final String? file;
  final String? url;
  final String? architecture;

  // shown as the catalogue wrote it, like 438 MB
  final String? size;
  final DownloadRole role;

  String get name {
    final source = file ?? url ?? label;
    final clean = source.split('?').first;
    return clean.substring(clean.lastIndexOf('/') + 1);
  }

  bool get isPackage => role == DownloadRole.package || role == DownloadRole.dependency;

  CatalogDownload withRole(DownloadRole r) =>
      CatalogDownload(label: label, file: file, url: url, architecture: architecture, size: size, role: r);
}

bool _hasPackageExtension(String name) {
  final lower = name.toLowerCase();
  return packageExtensions.any((e) => lower.endsWith('.$e'));
}

// the first package is the app, later ones are dependencies, unless the label says otherwise.
// a link with no package extension, like a releases page, can only be opened in a browser
List<CatalogDownload> classifyDownloads(List<CatalogDownload> raw, {bool variants = false}) {
  final out = <CatalogDownload>[];
  var haveMain = false;
  for (final d in raw) {
    final name = d.name.toLowerCase();
    if (name.endsWith('.sha256') || name.endsWith('.sha-256') || RegExp(r'checksum|sha-?256').hasMatch(d.label.toLowerCase())) {
      out.add(d.withRole(DownloadRole.checksum));
    } else if (name.endsWith('.zip') || name.endsWith('.7z')) {
      out.add(d.withRole(DownloadRole.archive));
    } else if (_hasPackageExtension(name)) {
      final dependency = RegExp(r'dependenc|framework|runtime').hasMatch(d.label.toLowerCase()) || name.startsWith('microsoft.');
      if (!dependency && (variants || !haveMain)) {
        haveMain = true;
        out.add(d.withRole(DownloadRole.package));
      } else {
        out.add(d.withRole(DownloadRole.dependency));
      }
    } else {
      out.add(d.withRole(DownloadRole.link));
    }
  }
  return out;
}

// 1.0.0 counts as 1.0.0.0, the template uses three parts and the packages use four
PackageVersion? parseLooseVersion(String? text) {
  if (text == null) return null;
  final parts = text.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '').split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final nums = [for (final p in parts) int.tryParse(p)];
  if (nums.contains(null)) return null;
  while (nums.length < 4) {
    nums.add(0);
  }
  return PackageVersion(nums[0]!, nums[1]!, nums[2]!, nums[3]!);
}

class CatalogApp {
  const CatalogApp({
    required this.slug,
    required this.base,
    required this.name,
    required this.summary,
    required this.versionText,
    required this.version,
    required this.updated,
    required this.developer,
    required this.category,
    required this.compatibility,
    required this.cover,
    required this.about,
    required this.downloads,
    required this.source,
    required this.package,
    this.aboutText,
    this.sourceId = '',
    this.sourceName = '',
    this.alsoFrom = const [],
    this.origins = const [],
  });

  final String slug;

  // the project folder, relative files and covers resolve against it
  final Uri base;
  final String name;
  final String summary;
  final String versionText;
  final PackageVersion? version;
  final String updated;
  final String developer;
  final String category;
  final List<String> compatibility;
  final String? cover;
  final String about;
  final List<CatalogDownload> downloads;
  final String source;

  // optional identity name from project.json, like BanditVault.Launcher
  final String? package;

  final String? aboutText;
  final String sourceId;
  final String sourceName;

  final List<CatalogApp> alsoFrom;

  final List<CatalogApp> origins;

  factory CatalogApp.fromJson(String slug, Uri base, Map<String, dynamic> j,
      {String sourceId = 'raccoon', String sourceName = 'Raccoon Dev Store'}) {
    String? str(String k) {
      final v = j[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final downloads = <CatalogDownload>[
      for (final d in (j['downloads'] as List? ?? const []))
        if (d is Map)
          CatalogDownload(
            label: (d['label'] as String?) ?? 'Download',
            file: (d['file'] as String?)?.trim().isEmpty == true ? null : d['file'] as String?,
            url: (d['url'] as String?)?.trim().isEmpty == true ? null : d['url'] as String?,
            architecture: d['architecture'] as String?,
            size: d['size'] as String?,
          ),
    ];
    return CatalogApp(
      slug: slug,
      base: base,
      name: str('name') ?? slug,
      summary: str('summary') ?? '',
      versionText: str('version') ?? '',
      version: parseLooseVersion(str('version')),
      updated: str('updated') ?? '',
      developer: str('developer') ?? '',
      category: str('category') ?? 'App',
      compatibility: [for (final c in (j['compatibility'] as List? ?? const [])) c.toString()],
      cover: str('cover'),
      about: str('about') ?? 'about.md',
      downloads: classifyDownloads(downloads),
      source: str('source') ?? '',
      package: str('package'),
      sourceId: sourceId,
      sourceName: sourceName,
    );
  }

  Uri resolve(CatalogDownload d) {
    if (d.url != null) return Uri.parse(d.url!);
    return base.resolve(Uri.encodeComponent(d.file ?? ''));
  }

  Uri? get coverUri => cover == null ? null : base.resolve(cover!);
  Uri get aboutUri => base.resolve(about);

  List<CatalogDownload> get packages => downloads.where((d) => d.role == DownloadRole.package).toList();

  CatalogApp copyWith({List<CatalogDownload>? downloads, List<CatalogApp>? origins, String? category}) => CatalogApp(
        slug: slug,
        base: base,
        name: name,
        summary: summary,
        versionText: versionText,
        version: version,
        updated: updated,
        developer: developer,
        category: category ?? this.category,
        compatibility: compatibility,
        cover: cover,
        about: about,
        downloads: downloads ?? this.downloads,
        source: source,
        package: package,
        aboutText: aboutText,
        sourceId: sourceId,
        sourceName: sourceName,
        alsoFrom: alsoFrom,
        origins: origins ?? this.origins,
      );

  CatalogApp withMain(CatalogDownload d) =>
      copyWith(downloads: [d, for (final x in downloads) if (!identical(x, d)) x]);

  CatalogDownload? get mainPackage => downloads.where((d) => d.role == DownloadRole.package).firstOrNull;
  List<CatalogDownload> get dependencies => downloads.where((d) => d.role == DownloadRole.dependency).toList();
  CatalogDownload? get archive => downloads.where((d) => d.role == DownloadRole.archive).firstOrNull;
  CatalogDownload? get checksum => downloads.where((d) => d.role == DownloadRole.checksum).firstOrNull;
  List<CatalogDownload> get links => downloads.where((d) => d.role == DownloadRole.link).toList();

  // only apps with a real package download can be sent to a console
  bool get installable => mainPackage != null || archive != null || resolvable;

  bool get resolvable => links.any((l) => isMediaFire(l.url) || isGithubRelease(l.url)) || githubRepo(source) != null;

  bool get hasFiles => mainPackage != null || archive != null;

  bool get needsResolving => !hasFiles && resolvable;
}

// installed against catalogue, as the pages show it
enum AppStatus { notInstalled, upToDate, updateAvailable, newerThanCatalogue }

class AppMatch {
  const AppMatch(this.app, this.installed, this.status);

  final CatalogApp app;
  final InstalledPackage? installed;
  final AppStatus status;
}

String? githubRepo(String url) {
  final m = RegExp(r'github\.com/([^/\s?#]+)/([^/\s?#]+)', caseSensitive: false).firstMatch(url);
  return m == null ? null : '${m.group(1)}/${m.group(2)}'.toLowerCase();
}

bool isMediaFire(String? url) => url != null && Uri.tryParse(url)?.host.endsWith('mediafire.com') == true;

bool isGithubRelease(String? url) =>
    url != null && url.contains('github.com') && RegExp(r'/releases(/|$)').hasMatch(url) && !url.contains('/releases/download/');

String normalizeCategory(String raw) {
  final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  return switch (key) {
    'media' || 'mediaapp' || 'mediaapps' => 'Media',
    'port' || 'ports' || 'gameport' || 'gameports' => 'Port',
    'emulator' || 'emulators' => 'Emulator',
    'frontend' || 'frontends' || 'launcher' || 'launchers' || 'gamelauncher' || 'gamelaunchers' => 'Frontend',
    'utility' || 'utilities' || 'tool' || 'tools' => 'Utility',
    'experimental' || 'experimentalapp' || 'experimentalapps' => 'Experimental',
    'app' || 'apps' || '' => 'App',
    _ => raw.trim(),
  };
}

final _desktopFile = RegExp(r'\.(exe|msi|dmg|deb|rpm|apk|appimage|pkg)$|(^|[-_.])(win|windows|win32|win64|linux|osx|macos|mac|android)([-_.]|$)', caseSensitive: false);

const _desktopTools = {'xboxmediatool', 'xbhomebrewvault', 'xbvault'};

bool isDesktopOnly(CatalogApp app) {
  if (_desktopTools.contains(app.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))) return true;
  if (app.compatibility.isNotEmpty && !app.compatibility.any((c) => c.toLowerCase().contains('xbox'))) return true;
  final files = [for (final d in app.downloads) if (d.role != DownloadRole.checksum && d.role != DownloadRole.dependency) d];
  return files.isNotEmpty && files.every((d) => _desktopFile.hasMatch(d.name));
}
