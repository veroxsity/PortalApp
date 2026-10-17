import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../portal/models.dart';
import 'models.dart';

const defaultCatalogueUrl = 'https://veroxsity.github.io/RaccoonDevStore/';

class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }

  void onCancel(void Function() f) => _listeners.add(f);
}

class CancelledException implements Exception {
  @override
  String toString() => 'Cancelled';
}

// layout follows raccoon dev store: catalog.json lists slugs, and each app has its own
// projects/<slug>/ folder with project.json, about.md and a cover
class CatalogClient {
  CatalogClient(String base) : base = Uri.parse(base.endsWith('/') ? base : '$base/');

  final Uri base;

  HttpClient _newHttp() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'PortalApp (+https://github.com/veroxsity/PortalApp)';

  Future<String> _text(Uri uri) async {
    final http = _newHttp();
    try {
      final req = await http.getUrl(uri).timeout(const Duration(seconds: 15));
      // the catalogue is edited by hand, so never serve a stale copy
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw PortalException('The catalogue answered ${resp.statusCode} for ${uri.path}.', status: resp.statusCode);
      }
      return await utf8.decodeStream(resp).timeout(const Duration(seconds: 30));
    } finally {
      http.close(force: true);
    }
  }

  Future<String> text(Uri uri) => _text(uri);

  Future<CatalogLoad> load() async {
    final index = jsonDecode(await _text(base.resolve('catalog.json')));
    if (index is! List) throw PortalException('catalog.json must be a list.');

    final apps = <CatalogApp>[];
    final failed = <String>[];
    await Future.wait([
      for (final slug in index.whereType<String>())
        () async {
          try {
            final folder = base.resolve('projects/${Uri.encodeComponent(slug)}/');
            final json = jsonDecode(await _text(folder.resolve('project.json')));
            if (json is Map) apps.add(CatalogApp.fromJson(slug, folder, json.cast<String, dynamic>()));
          } catch (_) {
            failed.add(slug);
          }
        }(),
    ]);
    // keep the catalogue's own order, the futures finish in any order
    final order = [for (final s in index.whereType<String>()) s];
    apps.sort((a, b) => order.indexOf(a.slug).compareTo(order.indexOf(b.slug)));
    return CatalogLoad(apps, failed);
  }

  Future<String> about(CatalogApp app) async => app.aboutText ?? await _text(app.aboutUri);

  Future<String> checksumFor(CatalogApp app, CatalogDownload d) async {
    final hash = parseChecksum(await _text(app.resolve(d)));
    if (hash == null) throw PortalException('The checksum file for ${app.name} could not be read.');
    return hash;
  }

  // streams to disk so a 600 MB package never sits in memory. github releases always
  // redirect, so redirects are followed
  Future<File> download(
    Uri uri,
    File dest, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    await dest.parent.create(recursive: true);
    final http = _newHttp();
    cancel?.onCancel(() => http.close(force: true));
    IOSink? sink;
    try {
      final req = await http.getUrl(uri).timeout(const Duration(seconds: 30));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        throw PortalException('The download answered ${resp.statusCode}.', status: resp.statusCode);
      }
      sink = dest.openWrite();
      var got = 0;
      await for (final chunk in resp) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(got, resp.contentLength);
      }
      await sink.close();
      sink = null;
      return dest;
    } catch (e) {
      await sink?.close().catchError((_) {});
      if (await dest.exists()) await dest.delete();
      // closing the client mid transfer surfaces as a socket error, which is the cancel
      if (cancel?.cancelled ?? false) throw CancelledException();
      rethrow;
    } finally {
      http.close(force: true);
    }
  }
}

class CatalogLoad {
  const CatalogLoad(this.apps, this.failed);

  final List<CatalogApp> apps;

  // slugs listed in catalog.json whose project.json could not be read
  final List<String> failed;
}

// the first 64 hex characters in the file, with or without a file name after them
String? parseChecksum(String text) => RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(text)?.group(0)?.toLowerCase();

Future<String> sha256Of(File f) async => (await sha256.bind(f.openRead()).first).toString();
