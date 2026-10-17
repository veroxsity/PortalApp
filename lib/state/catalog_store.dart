import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog_client.dart';
import '../catalog/matching.dart';
import '../catalog/models.dart';
import '../catalog/sources/devstore_source.dart';
import '../catalog/sources/merge.dart';
import '../catalog/sources/raccoon_source.dart';
import '../catalog/sources/revival_source.dart';
import '../catalog/sources/store_source.dart';
import '../portal/models.dart';
import '../portal/package_info.dart';

class StoreStatus {
  const StoreStatus({required this.id, required this.name, required this.enabled, this.count, this.error});

  final String id;
  final String name;
  final bool enabled;

  final int? count;
  final String? error;
}

class CatalogStore extends ChangeNotifier {
  CatalogStore({CatalogClient Function(String url)? clientFactory, List<StoreSource>? extraSources})
      : _factory = clientFactory ?? CatalogClient.new,
        _extra = extraSources ?? (clientFactory == null ? const [RevivalSource(), DevStoreSource()] : const []);

  final List<StoreSource> _extra;

  Map<String, String> sourceErrors = {};

  final CatalogClient Function(String url) _factory;

  static const _learnedKey = 'catalogue_learned';
  static const _disabledKey = 'stores_disabled';

  // raccoon dev store is the app's own catalogue, it is never disabled and never pointed elsewhere
  static const _raccoonId = 'raccoon';

  Set<String> _disabled = {};
  final Map<String, int> _counts = {};

  List<CatalogApp> apps = [];
  List<String> failed = [];
  bool loading = false;
  bool loaded = false;
  String? error;

  // slug to the package identity name it installed as, so updates are found without guessing
  Map<String, String> _learned = {};

  CatalogClient get client => _factory(defaultCatalogueUrl);

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _disabled = (prefs.getStringList(_disabledKey) ?? const []).toSet()..remove(_raccoonId);
      final raw = prefs.getString(_learnedKey);
      if (raw != null) _learned = (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {}
  }

  List<StoreSource> _sources() => [RaccoonSource(client), ..._extra]..sort((a, b) => a.priority.compareTo(b.priority));

  // raccoon has no switch, it is always on
  List<StoreStatus> get stores => [
        for (final src in _sources())
          if (src.id != _raccoonId)
            StoreStatus(
              id: src.id,
              name: src.name,
              enabled: !_disabled.contains(src.id),
              count: _counts[src.id],
              error: sourceErrors[src.name],
            ),
      ];

  Future<void> setStoreEnabled(String id, bool on) async {
    if (id == _raccoonId) return;
    final next = {..._disabled};
    if (on) {
      next.remove(id);
    } else {
      next.add(id);
      if (_sources().every((s) => next.contains(s.id))) return;
    }
    _disabled = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_disabledKey, _disabled.toList());
    } catch (_) {}
    await load();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    sourceErrors = {};
    notifyListeners();
    try {
      final c = client;
      final sources = [for (final src in _sources()) if (!_disabled.contains(src.id)) src];
      final results = await Future.wait([
        for (final src in sources)
          src.load(c.text).then<CatalogLoad?>((r) => r).catchError((Object e) {
            sourceErrors[src.name] = e is PortalException ? e.message : friendlyCatalogueError(e);
            return null;
          }),
      ]);
      final good = <CatalogLoad>[];
      for (var i = 0; i < sources.length; i++) {
        final r = results[i];
        if (r == null) continue;
        final kept = CatalogLoad([for (final a in r.apps) if (!isDesktopOnly(a)) a], r.failed);
        _counts[sources[i].id] = kept.apps.length;
        good.add(kept);
      }
      if (good.isEmpty) throw PortalException(sourceErrors.values.first);
      apps = [for (final a in mergeApps([for (final r in good) r.apps])) a.copyWith(category: normalizeCategory(a.category))];
      failed = [for (final r in good) ...r.failed];
      loaded = true;
    } catch (e) {
      error = e is PortalException ? e.message : friendlyCatalogueError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void learn(CatalogApp app, PackageInfo info) {
    _learned[app.slug] = info.name;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString(_learnedKey, jsonEncode(_learned))).catchError((_) => false);
  }

  AppMatch matchFor(CatalogApp app, List<InstalledPackage> installed) =>
      matchApp(app, installed, learnedName: _learned[app.slug]);

  List<AppMatch> matches(List<InstalledPackage> installed) => [for (final a in apps) matchFor(a, installed)];

  AppMatch? forInstalled(InstalledPackage p, List<InstalledPackage> installed) {
    for (final a in apps) {
      final m = matchFor(a, installed);
      if (m.installed?.fullName == p.fullName) return m;
    }
    return null;
  }
}

String friendlyCatalogueError(Object e) =>
    'The store could not be reached. Check this device is online, then try again.';
