import 'package:flutter/material.dart';

import '../catalog/models.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../theme/brand.dart';
import 'feedback.dart';
import 'markdown.dart';
import 'store_install_page.dart';
import 'widgets.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// 2026-09-17 as 17 Sep 2026, anything else as written
String formatDate(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return iso;
  final month = int.parse(m.group(2)!);
  if (month < 1 || month > 12) return iso;
  return '${int.parse(m.group(3)!)} ${_months[month - 1]} ${m.group(1)}';
}

String buildLabel(String file) {
  final dot = file.lastIndexOf('.');
  return (dot > 0 ? file.substring(0, dot) : file).replaceAll('_', ' ');
}

class StoreDetail extends StatefulWidget {
  const StoreDetail({super.key, required this.session, required this.catalog, required this.app});

  final ConsoleSession session;
  final CatalogStore catalog;
  final CatalogApp app;

  @override
  State<StoreDetail> createState() => _StoreDetailState();
}

class _StoreDetailState extends State<StoreDetail> {
  late Future<String> _about = widget.catalog.client.about(widget.app);

  String? _originId;
  String? _buildName;

  @override
  void didUpdateWidget(StoreDetail old) {
    super.didUpdateWidget(old);
    if (old.app.slug != widget.app.slug) {
      _about = widget.catalog.client.about(widget.app);
      _originId = null;
      _buildName = null;
    }
  }

  List<CatalogApp> get _origins => widget.app.origins.length > 1 ? widget.app.origins : [widget.app];

  CatalogApp get _origin {
    final list = _origins;
    return list.where((o) => o.sourceId == _originId).firstOrNull ?? list.where((o) => o.installable).firstOrNull ?? list.first;
  }

  CatalogApp get _target {
    final o = _origin;
    final pick = o.packages.where((d) => d.name == _buildName).firstOrNull;
    return pick == null ? o : o.withMain(pick);
  }

  Uri? get _browseStart {
    for (final l in _origin.links) {
      final u = Uri.tryParse(l.url ?? '');
      if (u != null && u.hasScheme) return u;
    }
    final src = Uri.tryParse(_origin.source);
    return src != null && src.hasScheme ? src : null;
  }

  Future<void> _browse(Uri start) async {
    final done = await browseAndInstall(context, widget.session, widget.catalog, _origin, start);
    if (done) await widget.session.refresh();
  }

  Future<void> _install() async {
    final done = await startStoreInstall(context, widget.session, widget.catalog, _target);
    if (done) await widget.session.refresh();
  }

  String _role(CatalogDownload d) => switch (d.role) {
        DownloadRole.package => 'App',
        DownloadRole.dependency => 'Installed with the app',
        DownloadRole.checksum => 'Used to check the download',
        DownloadRole.archive => 'Unpacked, then everything inside is installed',
        DownloadRole.link => 'Opens in your browser',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.session, widget.catalog]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final app = widget.app;
        final target = _target;
        final match = widget.catalog.matchFor(app, widget.session.packages);
        final main = target.mainPackage;
        final size = main?.size;

        Widget action;
        final String note;
        switch (match.status) {
          case AppStatus.notInstalled:
            action = FilledButton(onPressed: target.installable ? _install : null, child: Text(size == null ? 'Install' : 'Install  ·  $size'));
            note = target.installable
                ? 'Downloads it, checks it, and sends it to your console.'
                : 'This listing has no package that can be sent from here. Use the links below.';
          case AppStatus.updateAvailable:
            action = FilledButton(onPressed: target.installable ? _install : null, child: Text('Update to ${app.versionText}'));
            note = 'You have ${match.installed!.version}. The update goes over the top and keeps its saved data.';
          case AppStatus.upToDate:
            action = OutlinedButton(onPressed: target.installable ? _install : null, child: const Text('Reinstall'));
            note = 'Version ${match.installed!.version} is on your console, which is the latest here.';
          case AppStatus.newerThanCatalogue:
            action = const SizedBox.shrink();
            note = 'Your console has ${match.installed!.version}, which is newer than the ${app.versionText} listed here.';
        }

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _Cover(app: app),
            Padding(
              padding: const EdgeInsets.fromLTRB(Brand.s4, Brand.s5, Brand.s4, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.name, style: text.headlineMedium),
                if (app.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Brand.s2), child: Text(app.summary, style: text.bodyMedium?.copyWith(color: Brand.muted))),
                const SizedBox(height: Brand.s5),
                if (_origins.length > 1) ...[
                  Text('Install from', style: text.labelMedium?.copyWith(color: Brand.muted)),
                  const SizedBox(height: Brand.s2),
                  Wrap(spacing: Brand.s2, runSpacing: Brand.s2, children: [
                    for (final o in _origins)
                      ChoiceChip(
                        label: Text(o.versionText.isEmpty ? o.sourceName : '${o.sourceName}  ·  ${o.versionText}'),
                        selected: identical(o, _origin),
                        onSelected: o.installable ? (_) => setState(() {
                              _originId = o.sourceId;
                              _buildName = null;
                            }) : null,
                      ),
                  ]),
                  const SizedBox(height: Brand.s4),
                ],
                if (_origin.packages.length > 1) ...[
                  Text('Build', style: text.labelMedium?.copyWith(color: Brand.muted)),
                  const SizedBox(height: Brand.s2),
                  Wrap(spacing: Brand.s2, runSpacing: Brand.s2, children: [
                    for (final d in _origin.packages)
                      ChoiceChip(
                        label: Text(buildLabel(d.name)),
                        selected: d.name == (target.mainPackage?.name),
                        onSelected: (_) => setState(() => _buildName = d.name),
                      ),
                  ]),
                  const SizedBox(height: Brand.s4),
                ],
                if (match.status != AppStatus.newerThanCatalogue) SizedBox(width: double.infinity, child: action),
                Padding(padding: const EdgeInsets.only(top: Brand.s3), child: Text(note, style: text.bodySmall?.copyWith(fontSize: 13))),
                if (!target.installable && _browseStart != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Brand.s3),
                    child: SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => _browse(_browseStart!), child: const Text('Find the download'))),
                  ),
              ]),
            ),
            const SectionLabel('About this build'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Brand.s4),
              child: Column(children: [
                if (app.versionText.isNotEmpty) FactRow('Version', app.versionText),
                if (app.updated.isNotEmpty) FactRow('Updated', formatDate(app.updated)),
                if (app.developer.isNotEmpty) FactRow('Developer', app.developer),
                if (app.compatibility.isNotEmpty) FactRow('Works on', app.compatibility.join(', ')),
                FactRow('Category', app.category),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Brand.s4, Brand.s3, Brand.s4, 0),
              child: FutureBuilder<String>(
                future: _about,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return Text('Loading the details...', style: text.bodySmall);
                  }
                  if (snap.hasError || (snap.data ?? '').trim().isEmpty) {
                    return Text('More information is not available yet.', style: text.bodySmall);
                  }
                  return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: MarkdownView(snap.data!, onLink: (u) => openLink(context, u)));
                },
              ),
            ),
            if (app.downloads.isNotEmpty) ...[
              const SectionLabel('Files'),
              for (final d in app.downloads)
                ListRow(
                  title: d.label,
                  subtitle: [_role(d), if (d.architecture != null) d.architecture!, if (d.size != null) d.size!].join('  ·  '),
                  trailing: const Icon(Icons.open_in_new, size: 18, color: Brand.faint),
                  onTap: () {
                    final u = app.resolve(d);
                    d.role == DownloadRole.link ? _browse(u) : openLink(context, u.toString());
                  },
                ),
            ],
            if (app.source.isNotEmpty) ...[
              const SectionLabel('Source'),
              ListRow(
                title: 'Source code',
                subtitle: app.source,
                trailing: const Icon(Icons.open_in_new, size: 18, color: Brand.faint),
                onTap: () => openLink(context, app.source),
              ),
            ],
            const SizedBox(height: Brand.s7),
          ],
        );
      },
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.app});

  final CatalogApp app;

  @override
  Widget build(BuildContext context) {
    final uri = app.coverUri;
    final fallback = Center(child: Image.asset('assets/logo.png', width: 56, height: 56, opacity: const AlwaysStoppedAnimation(0.5)));
    return Container(
      height: 190,
      decoration: const BoxDecoration(color: Brand.raised2, border: Border(bottom: BorderSide(color: Brand.line))),
      child: uri == null
          ? fallback
          : Image.network(
              uri.toString(),
              fit: BoxFit.cover,
              cacheWidth: 1200,
              errorBuilder: (_, _, _) => fallback,
              frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : fallback,
            ),
    );
  }
}

// the phone version, the same view as a page of its own
class StoreDetailPage extends StatelessWidget {
  const StoreDetailPage({super.key, required this.session, required this.catalog, required this.app});

  final ConsoleSession session;
  final CatalogStore catalog;
  final CatalogApp app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: StoreDetail(session: session, catalog: catalog, app: app)),
      ),
    );
  }
}
