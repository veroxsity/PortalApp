import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/catalog/catalog_client.dart';
import 'package:portal_app/catalog/matching.dart';
import 'package:portal_app/catalog/models.dart';
import 'package:portal_app/portal/models.dart';
import 'package:portal_app/ui/markdown.dart';
import 'package:portal_app/ui/store_detail.dart' show formatDate;

final base = Uri.parse('https://example.com/store/projects/widget/');

// the three shapes raccoon dev store uses today
CatalogApp parse(Map<String, dynamic> j) => CatalogApp.fromJson('widget', base, j);

InstalledPackage installed(String name, String version, {String family = 'Acme.Widget', int origin = 5}) => InstalledPackage(
      fullName: '${family}_${version}_x64__abc',
      familyName: family,
      relativeId: '',
      name: name,
      publisher: '',
      version: PackageVersion.tryParse(version)!,
      origin: origin,
      canUninstall: true,
      uninstallDeniedReason: '',
      listed: true,
      users: const [],
    );

void main() {
  group('downloads', () {
    test('a package with its checksum', () {
      final app = parse({
        'name': 'ADFYT',
        'downloads': [
          {'label': 'Download APPX', 'file': 'ADFYT_1.0.1.0_x64.appx', 'size': '172 KB'},
          {'label': 'SHA-256 checksum', 'file': 'ADFYT_1.0.1.0_x64.appx.sha256'},
        ],
      });
      expect(app.mainPackage!.name, 'ADFYT_1.0.1.0_x64.appx');
      expect(app.checksum!.name, 'ADFYT_1.0.1.0_x64.appx.sha256');
      expect(app.dependencies, isEmpty);
      expect(app.installable, isTrue);
    });

    test('a dependency is told apart from the app', () {
      final app = parse({
        'name': 'T',
        'downloads': [
          {'label': 'Download MSIX', 'file': 'TModLoaderUWP_1.0.0.0_x64.msix'},
          {'label': 'Download VCLibs dependency', 'file': 'Microsoft.VCLibs.x64.14.00.appx'},
        ],
      });
      expect(app.mainPackage!.name, 'TModLoaderUWP_1.0.0.0_x64.msix');
      expect(app.dependencies.single.name, 'Microsoft.VCLibs.x64.14.00.appx');
    });

    test('a dependency listed first does not become the app', () {
      final app = parse({
        'name': 'T',
        'downloads': [
          {'label': 'Download VCLibs dependency', 'file': 'Microsoft.VCLibs.x64.14.00.appx'},
          {'label': 'Download APPX', 'file': 'App.appx'},
        ],
      });
      expect(app.mainPackage!.name, 'App.appx');
    });

    test('a releases page is resolved to real files when installing', () {
      final app = parse({
        'name': 'T',
        'downloads': [
          {'label': 'Download from GitHub', 'url': 'https://github.com/example/project/releases/latest'},
        ],
      });
      expect(app.installable, isTrue);
      expect(app.needsResolving, isTrue);
      expect(app.links.single.role, DownloadRole.link);
    });

    test('urls: absolute ones as they are, files beside project.json, odd names encoded', () {
      final app = parse({
        'name': 'T',
        'downloads': [
          {'label': 'a', 'url': 'https://github.com/x/y/releases/download/nightly/Big-nightly.appx?x=1'},
          {'label': 'b', 'file': 'My App (1).appx'},
        ],
      });
      expect(app.resolve(app.downloads[0]).toString(), 'https://github.com/x/y/releases/download/nightly/Big-nightly.appx?x=1');
      expect(app.downloads[0].name, 'Big-nightly.appx');
      expect(app.resolve(app.downloads[1]).toString(), 'https://example.com/store/projects/widget/My%20App%20(1).appx');
    });
  });

  test('missing fields fall back instead of throwing', () {
    final app = parse({});
    expect(app.name, 'widget');
    expect(app.category, 'App');
    expect(app.about, 'about.md');
    expect(app.coverUri, isNull);
    expect(app.downloads, isEmpty);
  });

  test('cover and about resolve beside project.json', () {
    final app = parse({'name': 'T', 'cover': 'cover.png'});
    expect(app.coverUri.toString(), 'https://example.com/store/projects/widget/cover.png');
    expect(app.aboutUri.toString(), 'https://example.com/store/projects/widget/about.md');
  });

  group('versions', () {
    test('three parts count as four', () {
      expect(parseLooseVersion('1.0.0'), const PackageVersion(1, 0, 0, 0));
      expect(parseLooseVersion('v2.1'), const PackageVersion(2, 1, 0, 0));
      expect(parseLooseVersion('nightly'), isNull);
      expect(parseLooseVersion('1.2.3.4.5'), isNull);
    });
  });

  group('matching', () {
    final app = parse({'name': 'Bandit Launcher', 'version': '1.0.0.57'});

    test('by display name, ignoring case and punctuation', () {
      final m = matchApp(app, [installed('bandit  launcher', '1.0.0.4', family: 'BanditVault.Launcher')]);
      expect(m.installed, isNotNull);
      expect(m.status, AppStatus.updateAvailable);
    });

    test('numeric version order decides the status', () {
      expect(matchApp(app, [installed('Bandit Launcher', '1.0.0.9')]).status, AppStatus.updateAvailable);
      expect(matchApp(app, [installed('Bandit Launcher', '1.0.0.57')]).status, AppStatus.upToDate);
      // 1.0.0.509 is newer than 1.0.0.57, which text order would get wrong
      expect(matchApp(app, [installed('Bandit Launcher', '1.0.0.509')]).status, AppStatus.newerThanCatalogue);
    });

    test('Microsoft apps with the same name are not matched', () {
      final edge = parse({'name': 'Microsoft Edge', 'version': '999'});
      expect(matchApp(edge, [installed('Microsoft Edge', '150.0.0.1', family: 'Microsoft.MicrosoftEdge.Stable', origin: 3)]).installed, isNull);
    });

    test('the package identity beats the name', () {
      final withId = parse({'name': 'Totally Different', 'version': '2.0.0.0', 'package': 'Acme.Widget'});
      final m = matchApp(withId, [installed('Whatever', '1.0.0.0')]);
      expect(m.status, AppStatus.updateAvailable);
    });

    test('a name learned from an install beats the name', () {
      final m = matchApp(app, [installed('Renamed Thing', '1.0.0.0')], learnedName: 'Acme.Widget');
      expect(m.installed, isNotNull);
    });

    test('not installed', () {
      expect(matchApp(app, [installed('Other', '1.0.0.0', family: 'Other.App')]).status, AppStatus.notInstalled);
    });
  });

  group('checksums', () {
    const hash = 'e70d10cbbaa13f9e31691267a7df1a7a2a11b6481b75def64df0555b64e36308';

    test('with a file name after the hash', () => expect(parseChecksum('$hash  ADFYT_1.0.1.0_x64.appx\n'), hash));
    test('bare, and upper case', () => expect(parseChecksum('${hash.toUpperCase()}\r\n'), hash));
    test('nothing usable', () => expect(parseChecksum('not a hash'), isNull));
  });

  group('markdown', () {
    test('headings, bullets and paragraphs', () {
      final blocks = parseMarkdown('Intro line\nstill intro\n\n## Before installing\n\n- one\n- two\n\nEnd.');
      expect(blocks[0], isA<MdParagraph>().having((b) => b.text, 'text', 'Intro line still intro'));
      expect(blocks[1], isA<MdHeading>().having((b) => b.level, 'level', 2));
      expect((blocks[2] as MdBullets).items, ['one', 'two']);
      expect(blocks[3], isA<MdParagraph>());
    });

    test('inline styles and links', () {
      final parts = parseInline('Use `VCLibs` with **care** and *thought*, see [docs](https://example.com/a).');
      expect(parts.where((p) => p.code).single.text, 'VCLibs');
      expect(parts.where((p) => p.bold).single.text, 'care');
      expect(parts.where((p) => p.italic).single.text, 'thought');
      expect(parts.where((p) => p.href != null).single.href, 'https://example.com/a');
    });

    test('only web links are followed', () {
      final parts = parseInline('[x](javascript:alert(1)) and [y](file:///c:/secret)');
      expect(parts.where((p) => p.href != null), isEmpty);
    });
  });

  test('dates read like the website', () {
    expect(formatDate('2026-09-17'), '17 Sep 2026');
    expect(formatDate('soon'), 'soon');
    expect(formatDate('2026-13-01'), '2026-13-01');
  });
}
