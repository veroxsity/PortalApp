import 'package:flutter/material.dart';

import '../catalog/models.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../theme/brand.dart';
import 'master_detail.dart';
import 'store_detail.dart';
import 'widgets.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key, required this.session, required this.catalog, required this.focus});

  final ConsoleSession session;
  final CatalogStore catalog;

  // another tab can ask the store to open a particular app
  final ValueNotifier<CatalogApp?> focus;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  final _search = TextEditingController();
  String _category = 'All';
  String? _selected;

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    _search.dispose();
    super.dispose();
  }

  void _onFocus() {
    final app = widget.focus.value;
    if (app == null) return;
    widget.focus.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(app);
    });
  }

  void _open(CatalogApp app) {
    if (MasterDetail.isWide(context)) {
      setState(() => _selected = app.slug);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoreDetailPage(session: widget.session, catalog: widget.catalog, app: app),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.session, catalog, _search]),
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        final matches = catalog.matches(widget.session.packages);
        final categories = {for (final a in catalog.apps) a.category}.toList()..sort();
        final shown = [
          for (final m in matches)
            if ((_category == 'All' || m.app.category == _category) &&
                (q.isEmpty || [m.app.name, m.app.summary, m.app.developer, m.app.category].join(' ').toLowerCase().contains(q)))
              m,
        ]..sort((a, b) => b.app.updated.compareTo(a.app.updated));
        final selected = catalog.apps.where((a) => a.slug == _selected).firstOrNull;

        final master = RefreshIndicator(
          onRefresh: catalog.load,
          color: Brand.accent,
          backgroundColor: Brand.raised2,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Brand.s6),
            children: [
              PageHeader(
                title: 'Store',
                subtitle: catalog.loaded ? '${catalog.apps.length} ${catalog.apps.length == 1 ? 'app' : 'apps'}' : 'Raccoon, Emulation Revival, Xbox Dev Store',
                trailing: IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: catalog.loading ? null : catalog.load),
              ),
              SearchField(controller: _search, hint: 'Search the store'),
              if (categories.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Brand.s4, vertical: Brand.s2),
                  child: Wrap(
                    spacing: Brand.s2,
                    children: [
                      for (final c in ['All', ...categories]) ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                    ],
                  ),
                ),
              if (catalog.loading && !catalog.loaded) ...[for (var i = 0; i < 4; i++) const SkeletonRow()],
              if (catalog.error != null && !catalog.loaded)
                SizedBox(
                  height: 300,
                  child: EmptyState(
                    title: 'The store is not reachable',
                    body: catalog.error!,
                    action: FilledButton(onPressed: catalog.loading ? null : catalog.load, child: const Text('Try again')),
                  ),
                ),
              if (catalog.loaded && catalog.apps.isEmpty)
                const SizedBox(height: 260, child: EmptyState(title: 'No apps yet', body: 'The catalogue is empty right now. Check back later.')),
              if (catalog.loaded && catalog.apps.isNotEmpty && shown.isEmpty)
                const SizedBox(height: 200, child: EmptyState(title: 'Nothing matched', body: 'Try another search, or choose All.')),
              for (final m in shown)
                ListRow(
                  leading: AppThumb(name: m.app.name, cover: m.app.coverUri, size: 48, aspect: 1.6),
                  title: m.app.name,
                  subtitle: m.app.summary,
                  selected: selected?.slug == m.app.slug,
                  trailing: switch (m.status) {
                    AppStatus.updateAvailable => const StatusPill('Update', kind: PillKind.update),
                    AppStatus.upToDate || AppStatus.newerThanCatalogue => const StatusPill('Installed'),
                    AppStatus.notInstalled => Text(m.app.versionText.isEmpty ? '' : 'v${m.app.versionText}', style: Theme.of(context).textTheme.bodySmall),
                  },
                  onTap: () => _open(m.app),
                ),
              if (catalog.failed.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(Brand.s4),
                  child: Text('${catalog.failed.length} listed ${catalog.failed.length == 1 ? 'app' : 'apps'} could not be loaded.', style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        );

        return MasterDetail(
          master: master,
          emptyHint: 'Select an app',
          detail: selected == null ? null : StoreDetail(key: ValueKey(selected.slug), session: widget.session, catalog: catalog, app: selected),
        );
      },
    );
  }
}
