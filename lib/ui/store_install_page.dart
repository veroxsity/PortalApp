import 'package:flutter/material.dart';

import '../browser/browser_page.dart';
import '../catalog/install_run.dart';
import '../catalog/models.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../theme/brand.dart';
import 'feedback.dart';
import 'keep_awake.dart';
import 'widgets.dart';

// opens the install screen and returns true when something was installed
Future<bool> startStoreInstall(BuildContext context, ConsoleSession session, CatalogStore catalog, CatalogApp app) async {
  final done = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => StoreInstallPage(session: session, catalog: catalog, app: app)),
  );
  return done ?? false;
}

Future<bool> browseAndInstall(BuildContext context, ConsoleSession session, CatalogStore catalog, CatalogApp app, Uri start) async {
  if (!BrowserPage.supported) {
    await openLink(context, start.toString());
    return false;
  }
  final got = await BrowserPage.open(context, start);
  if (got == null || !context.mounted) return false;
  final picked = app.copyWith(downloads: classifyDownloads([CatalogDownload(label: got.name, url: got.url.toString())], variants: true));
  return startStoreInstall(context, session, catalog, picked);
}

class StoreInstallPage extends StatefulWidget {
  const StoreInstallPage({super.key, required this.session, required this.catalog, required this.app});

  final ConsoleSession session;
  final CatalogStore catalog;
  final CatalogApp app;

  @override
  State<StoreInstallPage> createState() => _StoreInstallPageState();
}

class _StoreInstallPageState extends State<StoreInstallPage> {
  late InstallRun _run;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  void _begin() {
    keepAwake(true);
    _run = InstallRun(
      app: widget.app,
      catalog: widget.catalog.client,
      session: widget.session,
      onInstalled: widget.catalog.learn,
    )..start();
    // let the screen sleep again once it is over
    _run.addListener(() {
      if (_run.finished) keepAwake(false);
    });
  }

  @override
  void dispose() {
    keepAwake(false);
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _run,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final inDownload = _run.steps[0].state == StepStatus.active;
        return PopScope(
          // leaving mid-upload would leave the console with half a package
          canPop: !_run.running || inDownload,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop && _run.running) _run.cancel();
          },
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !_run.running || inDownload,
              title: Text(_run.finished ? (_run.failed ? 'Install failed' : 'Installed') : 'Installing'),
            ),
            body: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(Brand.s4),
                  children: [
                    Row(children: [
                      AppThumb(name: widget.app.name, cover: widget.app.coverUri, size: 56, aspect: 1.6),
                      const SizedBox(width: Brand.s4),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.app.name, style: text.titleLarge),
                          Text('Version ${widget.app.versionText}  ·  to ${widget.session.address}', style: text.bodySmall?.copyWith(fontSize: 13)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: Brand.s5),
                    for (var i = 0; i < _run.steps.length; i++) _StepTile(step: _run.steps[i], last: i == _run.steps.length - 1),
                    const SizedBox(height: Brand.s4),
                    if (_run.failed)
                      Container(
                        padding: const EdgeInsets.all(Brand.s4),
                        decoration: BoxDecoration(color: Brand.raised, borderRadius: BorderRadius.circular(10), border: Border.all(color: Brand.error)),
                        child: Text(_run.error!, style: text.bodyMedium),
                      ),
                    if (_run.finished && !_run.failed)
                      Text(
                        _run.updated
                            ? '${_run.result!.name} ${_run.result!.version} is on your console. Its saved data was not touched.'
                            : '${_run.result!.name} ${_run.result!.version} is on your console.',
                        style: text.bodyMedium,
                      ),
                    if (_run.running && !inDownload)
                      Text('Keep this screen open until it finishes.', style: text.bodySmall?.copyWith(fontSize: 13)),
                    const SizedBox(height: Brand.s5),
                    ..._actions(context),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _actions(BuildContext context) {
    if (_run.running) {
      return [
        if (_run.steps[0].state == StepStatus.active)
          OutlinedButton(onPressed: _run.cancel, child: const Text('Cancel')),
      ];
    }
    if (_run.failed) {
      return [
        FilledButton(
          onPressed: () => setState(() {
            _run.dispose();
            _begin();
          }),
          child: const Text('Try again'),
        ),
        const SizedBox(height: Brand.s3),
        OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
      ];
    }
    final p = _run.result;
    return [
      FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Done')),
      if (p != null && p.listed) ...[
        const SizedBox(height: Brand.s3),
        OutlinedButton(
          onPressed: () async {
            final ok = await attempt(context, () => widget.session.launch(p), address: widget.session.address);
            if (ok && context.mounted) Navigator.of(context).pop(true);
          },
          child: const Text('Open on console'),
        ),
      ],
    ];
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.last});

  final RunStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = step.state == StepStatus.pending;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: Column(children: [
            _Marker(step.state, step.fraction),
            if (!last) Expanded(child: Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Brand.line)),
          ]),
        ),
        const SizedBox(width: Brand.s3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Brand.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: muted ? Brand.faint : Brand.ink)),
              if (step.detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(step.detail, style: text.bodySmall?.copyWith(fontSize: 13))),
              if (step.state == StepStatus.active && step.fraction != null)
                Padding(
                  padding: const EdgeInsets.only(top: Brand.s2),
                  child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: step.fraction, minHeight: 4)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker(this.state, this.fraction);

  final StepStatus state;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case StepStatus.active:
        return SizedBox(width: 24, height: 24, child: Padding(padding: const EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.5, value: fraction)));
      case StepStatus.done:
        return const Icon(Icons.check_circle, size: 24, color: Brand.success);
      case StepStatus.failed:
        return const Icon(Icons.error, size: 24, color: Brand.error);
      case StepStatus.skipped:
        return const Icon(Icons.remove_circle_outline, size: 24, color: Brand.faint);
      case StepStatus.pending:
        return Container(
          width: 24,
          height: 24,
          padding: const EdgeInsets.all(5),
          child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.line, width: 2))),
        );
    }
  }
}
