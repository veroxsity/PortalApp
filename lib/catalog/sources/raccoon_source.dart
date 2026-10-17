import '../catalog_client.dart';
import 'store_source.dart';

class RaccoonSource extends StoreSource {
  const RaccoonSource(this.client);

  final CatalogClient client;

  @override
  String get id => 'raccoon';

  @override
  String get name => 'Raccoon Dev Store';

  @override
  int get priority => 0;

  @override
  Future<CatalogLoad> load(FetchText fetch) => client.load();
}
