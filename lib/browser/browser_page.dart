import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/brand.dart';
import 'request_filter.dart';

class BrowserDownload {
  const BrowserDownload(this.url, this.name);

  final Uri url;
  final String name;
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.start});

  final Uri start;

  static bool get supported => Platform.isWindows || Platform.isAndroid;

  static Future<BrowserDownload?> open(BuildContext context, Uri start) =>
      Navigator.of(context).push<BrowserDownload>(MaterialPageRoute(builder: (_) => BrowserPage(start: start)));

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _web;
  late Uri _page = widget.start;
  final _requests = ValueNotifier<int>(0);
  final _popups = ValueNotifier<int>(0);
  final _progress = ValueNotifier<double>(0);
  final _notice = ValueNotifier<String?>(null);
  bool _canBack = false;
  bool _captured = false;

  @override
  void dispose() {
    _requests.dispose();
    _popups.dispose();
    _progress.dispose();
    _notice.dispose();
    super.dispose();
  }

  void _capture(Uri url, String name) {
    if (_captured || !mounted) return;
    _captured = true;
    Navigator.of(context).pop(BrowserDownload(url, name));
  }

  WebResourceResponse _empty() => WebResourceResponse(contentType: 'text/plain', statusCode: 204, reasonPhrase: 'No Content', data: Uint8List(0));

  Future<void> _refreshBack() async {
    final can = await _web?.canGoBack() ?? false;
    if (mounted && can != _canBack) setState(() => _canBack = can);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_canBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _web?.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          title: Text(_page.host, style: text.titleMedium, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: _canBack ? () => _web?.goBack() : null),
            IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: () => _web?.reload()),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, p, _) => p > 0 && p < 1 ? LinearProgressIndicator(value: p, minHeight: 3) : const SizedBox(height: 3),
            ),
          ),
        ),
        body: Column(children: [
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri.uri(widget.start)),
              initialSettings: InAppWebViewSettings(
                useShouldInterceptRequest: true,
                useShouldOverrideUrlLoading: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: true,
                mediaPlaybackRequiresUserGesture: true,
                isInspectable: false,
              ),
              onWebViewCreated: (c) => _web = c,
              onLoadStart: (_, url) {
                final u = url == null ? null : Uri.tryParse(url.toString());
                if (u != null && u.hasScheme && mounted) setState(() => _page = u);
                _refreshBack();
              },
              onLoadStop: (_, _) => _refreshBack(),
              onProgressChanged: (_, p) => _progress.value = p / 100,
              shouldOverrideUrlLoading: (_, action) async {
                final url = Uri.tryParse(action.request.url?.toString() ?? '');
                if (url == null) return NavigationActionPolicy.ALLOW;
                final file = downloadFileName(url);
                if (file != null && (action.isForMainFrame)) {
                  _capture(url, file);
                  return NavigationActionPolicy.CANCEL;
                }
                if (!allowNavigation(from: _page, to: url, userGesture: action.hasGesture ?? false)) {
                  _requests.value++;
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
              shouldInterceptRequest: (_, request) async {
                final url = Uri.tryParse(request.url.toString());
                if (url == null) return null;
                final file = downloadFileName(url);
                if (file != null) {
                  _capture(url, file);
                  return _empty();
                }
                if (url != _page && blocksRequest(url, page: _page)) {
                  _requests.value++;
                  return _empty();
                }
                return null;
              },
              onCreateWindow: (_, _) async {
                _popups.value++;
                return false;
              },
              onDownloadStartRequest: (_, request) {
                final url = Uri.tryParse(request.url.toString());
                if (url == null) return;
                final name = downloadFileName(url) ?? (isInstallableName(request.suggestedFilename ?? '') ? request.suggestedFilename : null);
                if (name == null) {
                  _notice.value = '${request.suggestedFilename ?? 'That file'} is not an Xbox app package, so it was ignored.';
                  return;
                }
                _capture(url, name);
              },
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: _notice,
            builder: (_, note, _) => note == null
                ? const SizedBox.shrink()
                : Container(width: double.infinity, color: Brand.raised2, padding: const EdgeInsets.all(Brand.s3), child: Text(note, style: text.bodySmall)),
          ),
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
            padding: const EdgeInsets.symmetric(horizontal: Brand.s4, vertical: Brand.s2),
            child: ListenableBuilder(
              listenable: Listenable.merge([_requests, _popups]),
              builder: (_, _) => Text(
                'Blocked ${_requests.value} ads and trackers, ${_popups.value} popups. Pick the download and it goes straight to the installer.',
                style: text.bodySmall?.copyWith(color: Brand.muted),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
