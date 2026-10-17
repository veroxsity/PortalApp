import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/io.dart' hide Archive;
import 'package:portal_app/catalog/install_run.dart';
import 'package:portal_app/catalog/models.dart' show CatalogApp, isDesktopOnly, normalizeCategory;
import 'package:portal_app/catalog/sources/devstore_source.dart';
import 'package:portal_app/catalog/sources/link_resolver.dart';
import 'package:portal_app/catalog/sources/merge.dart';
import 'package:portal_app/catalog/sources/revival_source.dart';
import 'package:portal_app/catalog/sources/store_source.dart';

const revivalCard = '''
<div class="card" id="azahar">
  <a href="/previews/emulators-azahar.html" class="card-link" data-modal-trigger="azahar">
    <div class="card-image-container"><img src="/xbox-dev-mode/images/emulators/azahar.webp" alt="Azahar Logo" class="card-image"></div>
    <div class="card-content"><h3 class="card-title" id="azahar-title">Azahar</h3><p class="card-description">A Nintendo 3DS emulator</p></div>
  </a>
  <div class="card-modal-content" data-modal-id="azahar" style="display: none;">
    <ul class="info-list"><li class="app-version" data-app-id="azahar"><strong>Version:</strong> <span class="val">0.2126.2.1</span></li>
      <li class="app-release-date"><strong>Release date:</strong><span class="val"><time class="release-date" datetime="2026-10-14">October 14, 2026</time></span></li>
      <li><strong>Developer:</strong> <a href="https://github.com/azahar-emu">Azahar Team</a></li>
      <li><strong>Compatibility:</strong> Xbox Series S|X</li></ul>
    <div class="card-actions">
      <a href="https://github.com/danprice142/Azahar-UWP/releases/download/0.2126.2.1/Azahar_0.2126.2.1.msix" class="btn download-link">Download</a>
      <a href="https://github.com/danprice142/Azahar-UWP/tree/UWP" class="btn source-code-link">Source Code</a>
    </div>
  </div>
</div>
<div class="card" id="ruffle">
  <a href="/p" class="card-link"><div class="card-content"><h3 class="card-title">Ruffle</h3><p class="card-description">Flash</p></div></a>
  <div class="card-modal-content" style="display: none;">
    <ul class="info-list"><li class="app-version"><strong>Version:</strong> <span class="val">1.2.32.0</span></li></ul>
    <div class="card-actions"><a href="https://github.com/x/y/releases/download/r1/Ruffle-UWP-1.2.32.0.zip" class="btn download-link">Download</a></div>
  </div>
</div>
''';

const devCards = '''
<div class="row">
  <div class="col-md-4"><div class="card text-center">
    <img class="card-img-top" src="./img/xbdevstore.png" alt="XB Dev Store">
    <div class="card-body"><h5 class="card-title">New XB Dev Store</h5><p class="card-text">Our new store</p>
      <a href="https://emulationrevival.github.io" class="btn btn-dark">Official Page</a></div></div></div>
  <div class="col-md-4"><div class="card text-center">
    <img class="card-img-top" src="./img/azahar.png" alt="Azahar">
    <div class="card-body"><h5 class="card-title">Azahar 3DS</h5><p class="card-text">3DS</p>
      <a href="https://github.com/danprice142/Azahar-UWP/releases/download/0.2126.1.0/Azahar_0.2126.1.0.msix" class="btn btn-success">Download App</a>
      <a href="https://github.com/danprice142/Azahar-UWP" class="btn btn-dark">Official Page</a></div></div></div>
  <div class="col-md-4"><div class="card text-center">
    <img class="card-img-top" src="./img/old.png" alt="Old">
    <div class="card-body"><h5 class="card-title">Old Game</h5><p class="card-text">Legacy only</p>
      <a href="https://www.mediafire.com/file/abc/OldGame_1.0.0.0_x64.appx/file" class="btn btn-success">Download App</a></div></div></div>
</div>
''';

void main() {
  final revivalPage = Uri.parse('https://emulationrevival.github.io/xbox-dev-mode/emulators.html');
  final devPage = Uri.parse('https://xboxdevstore.github.io/');

  group('emulation revival', () {
    final apps = parseRevivalPage(revivalCard, revivalPage, 'Emulator');

    test('reads the card, the hidden details and the download', () {
      final a = apps.first;
      expect(a.slug, 'azahar');
      expect(a.name, 'Azahar');
      expect(a.summary, 'A Nintendo 3DS emulator');
      expect(a.versionText, '0.2126.2.1');
      expect(a.updated, '2026-10-14');
      expect(a.developer, 'Azahar Team');
      expect(a.compatibility, ['Xbox Series S|X']);
      expect(a.coverUri.toString(), 'https://emulationrevival.github.io/xbox-dev-mode/images/emulators/azahar.webp');
      expect(a.mainPackage!.name, 'Azahar_0.2126.2.1.msix');
      expect(a.source, 'https://github.com/danprice142/Azahar-UWP/tree/UWP');
      expect(a.installable, isTrue);
    });

    test('a zip is an archive to unpack, not a link', () {
      final r = apps[1];
      expect(r.mainPackage, isNull);
      expect(r.archive!.name, 'Ruffle-UWP-1.2.32.0.zip');
      expect(r.installable, isTrue);
    });
  });

  group('emulation revival api', () {
    final json = jsonEncode({
      'items': [
        {
          'id': 'jazz2',
          'title': 'Jazz Resurrection',
          'description': 'A platformer',
          'category': 'Ports',
          'compatibility': 'Xbox One & Series S|X',
          'requirements': ['Original game files'],
          'features': ['Multiplayer'],
          'imageUrl': 'https://emulationrevival.github.io/img/jazz2.webp',
          'version': '3.8.0',
          'releaseDate': '2026-08-22',
          'releaseNotesUrl': 'https://github.com/o/r/releases/tag/3.8.0',
          'setupGuideUrl': 'https://wiki.example/guide',
          'sourceCodeUrl': 'https://github.com/o/r',
          'downloads': [
            {'label': 'Download', 'url': 'https://github.com/o/r/releases/download/3.8.0/Jazz2_3.8.0_UWP.zip'},
          ],
          'contributors': {
            'developers': [{'name': 'Deathkiller'}],
          },
        },
        {
          'id': 'gz',
          'title': 'A Mod',
          'category': 'GZDoom Mods',
          'downloads': [
            {'label': 'ModDB', 'url': 'https://www.moddb.com/mods/x'},
          ],
        },
      ],
    });
    final apps = parseRevivalApi(json);

    test('reads the item, its archive and the details page text', () {
      final a = apps.first;
      expect(a.name, 'Jazz Resurrection');
      expect(a.developer, 'Deathkiller');
      expect(a.versionText, '3.8.0');
      expect(a.updated, '2026-08-22');
      expect(a.archive!.name, 'Jazz2_3.8.0_UWP.zip');
      expect(a.aboutText, contains('## You will need'));
      expect(a.aboutText, contains('- Original game files'));
      expect(a.aboutText, contains('[Setup guide](https://wiki.example/guide)'));
      expect(normalizeCategory(a.category), 'Port');
    });

    test('a mod that is only a web link stays a link', () {
      expect(apps[1].links.single.url, 'https://www.moddb.com/mods/x');
      expect(apps[1].hasFiles, isFalse);
    });

    test('a bad document is rejected so the page scraper can take over', () {
      expect(() => parseRevivalApi('{"nope":1}'), throwsFormatException);
    });
  });

  group('xbox dev store', () {
    final apps = parseDevStorePage(devCards, devPage);

    test('skips the card that only points at the new store', () {
      expect(apps.map((a) => a.name), ['Azahar 3DS', 'Old Game']);
    });

    test('takes the version from the release tag or file name', () {
      expect(apps.first.versionText, '0.2126.1.0');
      expect(apps.first.mainPackage!.name, 'Azahar_0.2126.1.0.msix');
      expect(apps.first.source, 'https://github.com/danprice142/Azahar-UWP');
    });

    test('a MediaFire page is kept as a link and resolved on install', () {
      expect(apps[1].installable, isTrue);
      expect(apps[1].needsResolving, isTrue);
      expect(apps[1].mainPackage, isNull);
      expect(apps[1].links.single.url, contains('mediafire.com'));
      expect(apps[1].versionText, '1.0.0.0');
    });
  });

  group('merge', () {
    final revival = parseRevivalPage(revivalCard, revivalPage, 'Emulator');
    final dev = parseDevStorePage(devCards, devPage);
    final merged = mergeApps([revival, dev]);

    test('the same app in both stores becomes one entry, different apps stay', () {
      expect(merged.map((a) => a.name), ['Azahar', 'Ruffle', 'Old Game']);
    });

    test('it is matched by the github repo even when the names differ', () {
      final azahar = merged.first;
      expect(azahar.alsoFrom.single.name, 'Azahar 3DS');
      expect(azahar.sourceName, 'Emulation Revival + Xbox Dev Store');
    });

    test('the newest version wins and the better store supplies the text', () {
      final azahar = merged.first;
      expect(azahar.versionText, '0.2126.2.1');
      expect(azahar.developer, 'Azahar Team');
    });

    test('two builds of one app inside a store are not merged together', () {
      final a = parseDevStorePage(devCards.replaceAll('Old Game', 'Azahar 3DS'), devPage);
      final out = mergeApps([a]);
      expect(out.length, a.length);
    });

    test('a store with a package covers one whose entry has none', () {
      final noPackage = parseRevivalPage(revivalCard.replaceAll('.msix', '.exe'), revivalPage, 'Emulator');
      final out = mergeApps([noPackage, dev]);
      expect(out.first.installable, isTrue);
      expect(out.first.mainPackage!.name, 'Azahar_0.2126.1.0.msix');
    });
  });

  group('versions', () {
    test('from a release tag, a file name, or nothing', () {
      expect(versionFromUrl('https://github.com/a/b/releases/download/v1.2.3/x.zip'), '1.2.3');
      expect(versionFromUrl('https://github.com/a/b/releases/download/latest/App_2.0.1.0_x64.msix'), '2.0.1.0');
      expect(versionFromUrl('https://github.com/a/b/releases/download/latest/App.msix'), isNull);
    });
  });

  group('unpacking a zip', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('unpack'));
    tearDown(() => dir.delete(recursive: true));

    Uint8List package(String name) {
      final a = Archive()
        ..addFile(ArchiveFile.bytes(
            'AppxManifest.xml',
            utf8.encode('<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">'
                '<Identity Name="$name" Publisher="CN=A" Version="1.0.0.0" ProcessorArchitecture="x64"/>'
                '<Properties><DisplayName>$name</DisplayName></Properties></Package>')))
        ..addFile(ArchiveFile.bytes('AppxSignature.p7x', utf8.encode('sig')));
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    test('the app comes first and microsoft frameworks follow it', () async {
      final z = Archive()
        ..addFile(ArchiveFile.bytes('Dependencies/Microsoft.VCLibs.x64.14.00.appx', package('Microsoft.VCLibs.140.00')))
        ..addFile(ArchiveFile.bytes('Game_1.0.0.0_x64.msix', package('Acme.Game')))
        ..addFile(ArchiveFile.bytes('readme.txt', utf8.encode('hi')));
      final zip = File('${dir.path}/game.zip')..writeAsBytesSync(ZipEncoder().encode(z));

      final files = await unpackPackages(zip, Directory('${dir.path}/out'));
      expect(files.map((f) => f.uri.pathSegments.last), ['Game_1.0.0.0_x64.msix', 'Microsoft.VCLibs.x64.14.00.appx']);
    });

    test('a 7z works the same way', () async {
      final path = '${dir.path}/game.7z';
      final w = await createArchiveFile(path, format: const SevenZWriteFormat());
      await w.addBytes(ArchiveEntrySpec(path: 'Microsoft.VCLibs.x64.14.00.appx'), package('Microsoft.VCLibs.140.00'));
      await w.addBytes(ArchiveEntrySpec(path: 'bin/Game_1.0.0.0_x64.appx'), package('Acme.Game'));
      await w.close();

      final files = await unpackPackages(File(path), Directory('${dir.path}/out7'));
      expect(files.length, 2);
      expect(files.first.path, contains('Game_1.0.0.0_x64.appx'));
    });

    test('a zip with no package says so', () async {
      final z = Archive()..addFile(ArchiveFile.bytes('readme.txt', utf8.encode('hi')));
      final zip = File('${dir.path}/empty.zip')..writeAsBytesSync(ZipEncoder().encode(z));
      expect(() => unpackPackages(zip, Directory('${dir.path}/out2')), throwsA(anything));
    });
  });

  group('resolving links', () {
    test('mediafire: the button holds the direct file', () {
      const open = '<a class="input popsok" aria-label="Download file" id="downloadButton" href="https://download1.mediafire.com/abc/def/App.zip">Download</a>';
      expect(parseMediaFire(open), 'https://download1.mediafire.com/abc/def/App.zip');
      final scrambled = base64.encode(utf8.encode('https://download2.mediafire.com/x/y/App.zip'));
      expect(parseMediaFire('<a id="downloadButton" href="#" data-scrambled-url="$scrambled">Download</a>'), 'https://download2.mediafire.com/x/y/App.zip');
      expect(parseMediaFire('<html>nothing</html>'), isNull);
    });

    final release = jsonEncode({
      'assets': [
        {'name': 'App_1.0.0.0_x64.msixbundle', 'browser_download_url': 'https://github.com/o/r/releases/download/v1/App_1.0.0.0_x64.msixbundle', 'size': 52428800},
        {'name': 'App_1.0.0.0_arm64.msixbundle', 'browser_download_url': 'https://github.com/o/r/releases/download/v1/App_1.0.0.0_arm64.msixbundle', 'size': 52428800},
        {'name': 'Source code.zip', 'browser_download_url': 'https://github.com/o/r/archive/v1.zip', 'size': 1000},
        {'name': 'notes.txt', 'browser_download_url': 'https://github.com/o/r/releases/download/v1/notes.txt', 'size': 10},
      ],
    });

    test('github: keeps installable files and drops other cpus and source', () {
      final names = pickGithubAssets(release).map((d) => d.name);
      expect(names, ['App_1.0.0.0_x64.msixbundle']);
    });

    test('a repo-only listing becomes installable files', () async {
      final app = parseDevStorePage(devCards, devPage).last.copyWith();
      final resolver = LinkResolver((uri) async {
        if (uri.host == 'www.mediafire.com') return '<a id="downloadButton" href="https://download9.mediafire.com/k/OldGame_1.0.0.0_x64.appx">x</a>';
        throw StateError('unexpected $uri');
      });
      final out = await resolver.resolve(app);
      expect(out.mainPackage!.name, 'OldGame_1.0.0.0_x64.appx');
    });

    test('an app with only a github page asks the releases api', () async {
      final app = parseDevStorePage(devCards.replaceAll('https://www.mediafire.com/file/abc/OldGame_1.0.0.0_x64.appx/file', 'https://github.com/o/r/releases'), devPage).last;
      final asked = <Uri>[];
      final out = await LinkResolver((uri) async {
        asked.add(uri);
        return release;
      }).resolve(app);
      expect(asked.single.toString(), 'https://api.github.com/repos/o/r/releases/latest');
      expect(out.mainPackage!.name, 'App_1.0.0.0_x64.msixbundle');
    });
  });

  test('category names that mean the same shelf become one', () {
    expect(['Media', 'Media app', 'media apps'].map(normalizeCategory).toSet(), {'Media'});
    expect(['Port', 'Game port', 'Ports'].map(normalizeCategory).toSet(), {'Port'});
    expect(['Frontend', 'Game launcher'].map(normalizeCategory).toSet(), {'Frontend'});
    expect(normalizeCategory('Something New'), 'Something New');
  });

  test('pc and phone tools are not offered for a console', () {
    CatalogApp app(String name, List<String> compat, List<String> files) => parseRevivalApi(jsonEncode({
          'items': [
            {
              'id': name,
              'title': name,
              'compatibility': compat.isEmpty ? null : compat.first,
              'downloads': [for (final f in files) {'label': 'Download', 'url': 'https://github.com/o/r/releases/download/v1/$f'}],
            },
          ],
        })).single;
    expect(isDesktopOnly(app('USB Tool', ['Windows OS'], ['Tool.exe'])), isTrue);
    expect(isDesktopOnly(app('Vault', ['Desktop'], ['XBVault-v2.0.7-win-x64.zip'])), isTrue);
    expect(isDesktopOnly(app('Setup only', [], ['App-win-x64-setup.exe', 'App-linux-x64.zip'])), isTrue);
    expect(isDesktopOnly(app('Xbox Media Tool', [], ['XboxMediaUSB.v2.2.zip'])), isTrue);
    expect(isDesktopOnly(app('Game', ['Xbox One & Series S|X'], ['Game_1.0.0.0_x64.msix'])), isFalse);
    expect(isDesktopOnly(app('Game zip', [], ['Game-UWP-1.0.zip'])), isFalse);
  });
}
