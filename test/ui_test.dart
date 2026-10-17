import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/catalog/catalog_client.dart';
import 'package:portal_app/catalog/models.dart';
import 'package:portal_app/portal/portal_client.dart';
import 'package:portal_app/state/catalog_store.dart';
import 'package:portal_app/state/console_session.dart';
import 'package:portal_app/ui/installed_page.dart';
import 'package:portal_app/ui/shell.dart';
import 'package:portal_app/ui/store_page.dart';

Map<String, dynamic> pkgJson(String name, String family, String version, {int origin = 5, bool listed = true, bool canUninstall = true}) {
  final v = version.split('.').map(int.parse).toList();
  return {
    'PackageFullName': '${family}_${version}_x64__abc',
    'PackageFamilyName': family,
    'PackageRelativeId': '${family}_abc!App',
    'Name': name,
    'Publisher': 'CN=BanditVault',
    'PackageOrigin': origin,
    'AppListEntry': listed ? 1 : 0,
    'CanUninstall': canUninstall,
    'Version': {'Major': v[0], 'Minor': v[1], 'Build': v[2], 'Revision': v[3]},
    'RegisteredUsers': [],
  };
}

class FakeConsole extends PortalClient {
  FakeConsole(this.json) : super('10.0.0.1');

  List<Map<String, dynamic>> json;
  Set<String> running = {};
  final calls = <String>[];

  @override
  Future<List<InstalledPackage>> packages() async => [for (final j in json) InstalledPackage.fromJson(j)];

  @override
  Future<Set<String>> runningPackages() async => running;

  @override
  Future<void> launch(InstalledPackage p) async => calls.add('launch ${p.name}');

  @override
  Future<bool> closeApp(InstalledPackage p) async {
    calls.add('close ${p.name}');
    return true;
  }

  @override
  Future<void> uninstall(InstalledPackage p) async {
    calls.add('delete ${p.name}');
    json = [for (final j in json) if (j['PackageFullName'] != p.fullName) j];
  }

  @override
  Future<InstalledPackage> install(
    File package, {
    List<File> dependencies = const [],
    required String familyPrefix,
    String? expectedVersion,
    Progress? onUpload,
    void Function(InstallState)? onState,
  }) async {
    calls.add('install ${package.uri.pathSegments.last}');
    onUpload?.call(100, 100);
    json = [pkgJson('Widget', 'Acme.Widget', expectedVersion!)];
    return InstalledPackage.fromJson(json.first);
  }
}

List<int> appxBytes(String version) {
  final a = Archive();
  a.addFile(ArchiveFile.bytes(
      'AppxManifest.xml',
      utf8.encode('<Package><Identity Name="Acme.Widget" Publisher="CN=Acme" Version="$version" ProcessorArchitecture="x64"/>'
          '<Properties><DisplayName>Widget</DisplayName></Properties></Package>')));
  a.addFile(ArchiveFile.bytes('AppxSignature.p7x', [1]));
  return ZipEncoder().encode(a);
}

class FakeCatalog extends CatalogClient {
  FakeCatalog() : super('https://example.com/');

  @override
  Future<String> about(CatalogApp app) async => '## Before installing\n\n- An Xbox in Developer Mode\n\nBack up your saves first.';

  @override
  Future<File> download(Uri uri, File dest, {void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    await dest.writeAsBytes(appxBytes('1.0.0.4'));
    onProgress?.call(10, 10);
    return dest;
  }
}

CatalogApp storeApp(String slug, String name, String version, {String category = 'Media app', String updated = '2026-09-01', List<Map<String, String>>? downloads}) =>
    CatalogApp.fromJson(slug, Uri.parse('https://example.com/projects/$slug/'), {
      'name': name,
      'summary': '$name does a useful thing.',
      'version': version,
      'updated': updated,
      'developer': 'BanditVault',
      'category': category,
      'compatibility': ['Xbox Series S'],
      'downloads': downloads ??
          [
            {'label': 'Download APPX', 'file': '$slug.appx', 'size': '12 MB'},
          ],
    });

void main() {
  late ConsoleSession session;
  late FakeConsole console;
  late CatalogStore catalog;

  Future<void> setUpWorld({List<Map<String, dynamic>>? installed, List<CatalogApp>? apps}) async {
    console = FakeConsole(installed ??
        [
          pkgJson('Widget', 'Acme.Widget', '1.0.0.3'),
          pkgJson('Gadget', 'Acme.Gadget', '2.0.0.0'),
          pkgJson('Xbox Guide', 'Xbox.Guide', '9.0.0.0', origin: 3),
        ]);
    session = ConsoleSession(console);
    await session.refresh();
    catalog = CatalogStore(clientFactory: (_) => FakeCatalog());
    catalog.apps = apps ??
        [
          storeApp('widget', 'Widget', '1.0.0.4'),
          storeApp('gadget', 'Gadget', '2.0.0.0'),
          storeApp('newthing', 'New Thing', '0.5.0.0', category: 'Game port', updated: '2026-09-20'),
        ];
    catalog.loaded = true;
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: home);

  group('installed', () {
    testWidgets('updates come first, console apps are hidden', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));

      expect(find.text('UPDATES'), findsOneWidget);
      expect(find.text('1.0.0.3  →  1.0.0.4'), findsOneWidget);
      expect(find.text('Gadget'), findsOneWidget);
      expect(find.text('Xbox Guide'), findsNothing);
      // updates sit above the rest
      expect(tester.getTopLeft(find.text('Widget')).dy, lessThan(tester.getTopLeft(find.text('Gadget')).dy));
      // no row of tiny buttons, a row is one tap target
      expect(find.byTooltip('Delete'), findsNothing);
      expect(find.byTooltip('Launch'), findsNothing);
    });

    testWidgets('an empty console teaches what to do', (tester) async {
      phone(tester);
      await setUpWorld(installed: []);
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));
      expect(find.text('Nothing installed yet'), findsOneWidget);
      expect(find.text('Install from a file'), findsOneWidget);
    });

    testWidgets('search filters', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));
      await tester.enterText(find.byType(TextField), 'gad');
      await tester.pump();
      expect(find.text('Gadget'), findsOneWidget);
      expect(find.text('Widget'), findsNothing);
    });

    testWidgets('tapping a row opens the app, with one clear next step', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));

      await tester.tap(find.text('Gadget'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Launch'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Files'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Launch'));
      await tester.pumpAndSettle();
      expect(console.calls, ['launch Gadget']);
      expect(find.widgetWithText(FilledButton, 'Close'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(console.calls.last, 'close Gadget');
    });

    testWidgets('an app with nothing to launch shows no Launch button', (tester) async {
      phone(tester);
      await setUpWorld(installed: [pkgJson('Quiet', 'Acme.Quiet', '1.0.0.0', listed: false)], apps: []);
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));
      await tester.tap(find.text('Quiet'));
      await tester.pumpAndSettle();
      expect(find.text('Launch'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Files'), findsOneWidget);
      expect(find.textContaining('cannot be launched from here'), findsOneWidget);
    });

    testWidgets('an app with an update makes Update the primary action', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));

      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Update to 1.0.0.4'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Launch'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Launch'), findsOneWidget);
    });

    testWidgets('delete asks first and then leaves the page', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));
      await tester.tap(find.text('Gadget'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Delete from console'));
      await tester.tap(find.text('Delete from console'));
      await tester.pumpAndSettle();
      expect(find.textContaining('everything it has saved'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(console.calls, isEmpty);

      await tester.tap(find.text('Delete from console'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(console.calls, ['delete Gadget']);
      expect(find.text('Gadget'), findsNothing);
    });

    testWidgets('wide screens show the app beside the list', (tester) async {
      desktop(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: InstalledPage(session: session, catalog: catalog, onOpenInStore: (_) {}))));
      expect(find.text('Select an app'), findsOneWidget);

      await tester.tap(find.text('Gadget'));
      await tester.pumpAndSettle();
      // still the list, with the detail beside it
      expect(find.text('Installed'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Launch'), findsOneWidget);
    });
  });

  group('store', () {
    testWidgets('lists apps with their state', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: StorePage(session: session, catalog: catalog, focus: ValueNotifier(null)))));

      expect(find.text('Widget'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Installed'), findsOneWidget);
      expect(find.text('v0.5.0.0'), findsOneWidget);
      // newest first
      expect(tester.getTopLeft(find.text('New Thing')).dy, lessThan(tester.getTopLeft(find.text('Widget')).dy));
    });

    testWidgets('category chips and search narrow the list', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: StorePage(session: session, catalog: catalog, focus: ValueNotifier(null)))));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Game port'));
      await tester.pump();
      expect(find.text('New Thing'), findsOneWidget);
      expect(find.text('Widget'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.enterText(find.byType(TextField), 'gadget');
      await tester.pump();
      expect(find.text('Gadget'), findsOneWidget);
      expect(find.text('Widget'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('Nothing matched'), findsOneWidget);
    });

    testWidgets('an unreachable store says so and offers a retry', (tester) async {
      phone(tester);
      await setUpWorld(apps: []);
      catalog.loaded = false;
      catalog.error = 'The store could not be reached.';
      await tester.pumpWidget(app(Scaffold(body: StorePage(session: session, catalog: catalog, focus: ValueNotifier(null)))));
      expect(find.text('The store is not reachable'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('detail offers the right button for each state', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: StorePage(session: session, catalog: catalog, focus: ValueNotifier(null)))));

      await tester.tap(find.text('New Thing'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Install  ·  12 MB'), findsOneWidget);
      expect(find.text('Before installing'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Update to 1.0.0.4'), findsOneWidget);
      expect(find.textContaining('keeps its saved data'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gadget'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Reinstall'), findsOneWidget);
    });

    testWidgets('an update runs through the steps and finishes', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Scaffold(body: StorePage(session: session, catalog: catalog, focus: ValueNotifier(null)))));
      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Update to 1.0.0.4'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Installed'), findsWidgets);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Send to console'), findsOneWidget);
      // this one went over an older copy, so it says its data was kept
      expect(find.textContaining('Its saved data was not touched'), findsOneWidget);
      expect(console.calls, ['install widget.appx']);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    });
  });

  group('shell', () {
    testWidgets('phone: bottom bar, with a badge for updates', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Shell(session: session, catalog: catalog, onDisconnect: () {})));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);

      await tester.tap(find.text('Store'));
      await tester.pumpAndSettle();
      expect(find.text('3 apps'), findsOneWidget);

      await tester.tap(find.text('Console'));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      expect(find.textContaining('10.0.0.1:11443'), findsOneWidget);
    });

    testWidgets('desktop: a rail instead', (tester) async {
      desktop(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Shell(session: session, catalog: catalog, onDisconnect: () {})));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('View in store jumps to the store entry', (tester) async {
      phone(tester);
      await setUpWorld();
      await tester.pumpWidget(app(Shell(session: session, catalog: catalog, onDisconnect: () {})));

      await tester.tap(find.text('Gadget'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('Raccoon Dev Store lists'));
      await tester.tap(find.textContaining('Raccoon Dev Store lists'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Reinstall'), findsOneWidget);
    });
  });
}
