import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/catalog/catalog_client.dart';
import 'package:portal_app/catalog/sources/devstore_source.dart';
import 'package:portal_app/catalog/sources/store_source.dart';
import 'package:portal_app/state/catalog_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String card(String name, String file) => '''
<div class="card"><img class="card-img-top" src="./i.png"><div class="card-body"><h5 class="card-title">$name</h5><p class="card-text">x</p>
<a href="https://github.com/o/$name/releases/download/v1/$file" class="btn">Download App</a></div></div>''';

class _Raccoon extends CatalogClient {
  _Raccoon() : super('https://example.com/');

  @override
  Future<CatalogLoad> load() async => CatalogLoad(parseDevStorePage(card('Alpha', 'Alpha_1.0.0.0_x64.msix'), Uri.parse('https://x/')), const []);
}

class _Other extends StoreSource {
  const _Other({this.fail = false});

  final bool fail;

  @override
  String get id => 'other';

  @override
  String get name => 'Other Store';

  @override
  int get priority => 1;

  @override
  Future<CatalogLoad> load(FetchText fetch) async {
    if (fail) throw Exception('down');
    return CatalogLoad(parseDevStorePage(card('Beta', 'Beta_1.0.0.0_x64.msix'), Uri.parse('https://y/')), const []);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  CatalogStore make({bool fail = false}) => CatalogStore(clientFactory: (_) => _Raccoon(), extraSources: [_Other(fail: fail)]);

  test('every store is on to begin with and reports how many apps it gave', () async {
    final s = make();
    await s.load();
    expect(s.apps.map((a) => a.name), ['Alpha', 'Beta']);
    // raccoon has no switch, only the other store shows up to toggle
    expect(s.stores.map((t) => (t.name, t.enabled, t.count)), [('Other Store', true, 1)]);
  });

  test('switching a store off drops its apps and is remembered', () async {
    final s = make();
    await s.load();
    await s.setStoreEnabled('other', false);
    expect(s.apps.map((a) => a.name), ['Alpha']);
    expect(s.stores.last.enabled, isFalse);

    final again = make();
    await again.restore();
    await again.load();
    expect(again.apps.map((a) => a.name), ['Alpha']);
  });

  test('raccoon dev store has no switch and cannot be turned off', () async {
    final s = make();
    await s.load();
    expect(s.stores.any((t) => t.id == 'raccoon'), isFalse);

    await s.setStoreEnabled('other', false);
    await s.setStoreEnabled('raccoon', false);
    expect(s.apps.map((a) => a.name), ['Alpha']);

    final again = make();
    await again.restore();
    await again.load();
    expect(again.apps.map((a) => a.name), contains('Alpha'));
  });

  test('a saved setting from before raccoon was locked on is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'stores_disabled': ['raccoon', 'other'],
    });
    final s = make();
    await s.restore();
    await s.load();
    expect(s.apps.map((a) => a.name), ['Alpha']);
    expect(s.stores.single.enabled, isFalse);
  });

  test('a store that fails shows its error while the others still load', () async {
    final s = make(fail: true);
    await s.load();
    expect(s.apps.map((a) => a.name), ['Alpha']);
    expect(s.loaded, isTrue);
    expect(s.stores.last.error, isNotNull);
  });
}
