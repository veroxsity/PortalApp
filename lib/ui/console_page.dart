import 'package:flutter/material.dart';

import '../catalog/catalog_client.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../theme/brand.dart';
import 'feedback.dart';
import 'install_page.dart';
import 'screenshot_page.dart';
import 'widgets.dart';

class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key, required this.session, required this.catalog, required this.onDisconnect});

  final ConsoleSession session;
  final CatalogStore catalog;
  final VoidCallback onDisconnect;

  Future<void> _editCatalogue(BuildContext context) async {
    final value = await showDialog<String>(context: context, builder: (_) => _CatalogueDialog(current: catalog.url));
    if (value != null) await catalog.setUrl(value);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([session, catalog]),
      builder: (context, _) {
        final custom = catalog.url != defaultCatalogueUrl;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.only(bottom: Brand.s6),
              children: [
                const PageHeader(title: 'Console'),
                const SectionLabel('Connection'),
                ListRow(
                  leading: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Brand.success, shape: BoxShape.circle)),
                  title: 'Connected',
                  subtitle: session.client.describe(session.packages.length),
                  trailing: TextButton(onPressed: onDisconnect, child: const Text('Disconnect')),
                ),
                const SectionLabel('Tools'),
                ListRow(
                  title: 'Install from a file',
                  subtitle: 'A signed .appx, .msix or bundle from this device',
                  trailing: const Icon(Icons.chevron_right, color: Brand.faint),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstallPage(session: session)));
                    if (context.mounted) attempt(context, session.refresh, address: session.address);
                  },
                ),
                ListRow(
                  title: 'Console screen',
                  subtitle: 'See what the console is showing right now',
                  trailing: const Icon(Icons.chevron_right, color: Brand.faint),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScreenshotPage(session: session))),
                ),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: Brand.s4),
                  title: Text('Show console apps', style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Text('Include Microsoft\'s own apps in the Installed list', style: text.bodySmall?.copyWith(fontSize: 13)),
                  value: session.showSystemApps,
                  activeThumbColor: Brand.accentInk,
                  activeTrackColor: Brand.accent,
                  onChanged: session.setShowSystemApps,
                ),
                const Divider(),
                const SectionLabel('Stores'),
                for (final st in catalog.stores)
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: Brand.s4),
                    title: Text(st.name, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      !st.enabled
                          ? 'Off'
                          : st.error != null
                              ? st.error!
                              : st.count == null
                                  ? 'Loading'
                                  : '${st.count} ${st.count == 1 ? 'app' : 'apps'}',
                      style: text.bodySmall?.copyWith(fontSize: 13, color: st.enabled && st.error != null ? Brand.error : null),
                    ),
                    value: st.enabled,
                    activeThumbColor: Brand.accentInk,
                    activeTrackColor: Brand.accent,
                    onChanged: (on) => catalog.setStoreEnabled(st.id, on),
                  ),
                ListRow(
                  title: 'Raccoon catalogue address',
                  subtitle: custom ? catalog.url : 'Default',
                  trailing: const Icon(Icons.edit_outlined, size: 18, color: Brand.faint),
                  onTap: () => _editCatalogue(context),
                ),
                if (custom)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Brand.s2),
                      child: TextButton(onPressed: () => catalog.setUrl(''), child: const Text('Use Raccoon Dev Store')),
                    ),
                  ),
                ListRow(
                  title: 'Reload stores',
                  subtitle: catalog.loading ? 'Loading' : 'Fetch every store again',
                  trailing: const Icon(Icons.refresh, size: 18, color: Brand.faint),
                  onTap: catalog.loading ? null : catalog.load,
                ),
                const SectionLabel('About'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Brand.s4),
                  child: Row(children: [
                    Image.asset('assets/logo.png', width: 36, height: 36),
                    const SizedBox(width: Brand.s3),
                    Expanded(child: Text('PortalApp manages an Xbox in Developer Mode through its Device Portal. Not affiliated with Microsoft or Xbox.', style: text.bodySmall?.copyWith(fontSize: 13))),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// owns its controller, so it is disposed with the dialog and not while it is still animating out
class _CatalogueDialog extends StatefulWidget {
  const _CatalogueDialog({required this.current});

  final String current;

  @override
  State<_CatalogueDialog> createState() => _CatalogueDialogState();
}

class _CatalogueDialogState extends State<_CatalogueDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catalogue address'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('A web address for a catalogue laid out like Raccoon Dev Store.'),
        const SizedBox(height: Brand.s3),
        TextField(controller: _controller, autofocus: true, keyboardType: TextInputType.url, onSubmitted: (v) => Navigator.pop(context, v)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Save')),
      ],
    );
  }
}
