import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/browser/request_filter.dart';

void main() {
  final page = Uri.parse('https://www.mediafire.com/file/abc/App.zip/file');

  group('ads', () {
    test('known ad networks are blocked, subdomains included', () {
      expect(blocksRequest(Uri.parse('https://ads.doubleclick.net/x.js'), page: page), isTrue);
      expect(blocksRequest(Uri.parse('https://pagead2.googlesyndication.com/pagead/js/a.js'), page: page), isTrue);
      expect(blocksRequest(Uri.parse('https://cdn.taboola.com/libtrc/x.js'), page: page), isTrue);
    });

    test('the site and its own cdn are left alone', () {
      expect(blocksRequest(Uri.parse('https://static.mediafire.com/css/site.css'), page: page), isFalse);
      expect(blocksRequest(Uri.parse('https://cdn.jsdelivr.net/npm/x.js'), page: page), isFalse);
      expect(blocksRequest(Uri.parse('https://notdoubleclick.net.example.com/x'), page: page), isFalse);
    });

    test('ad-looking paths on another site are blocked but not on the page itself', () {
      expect(blocksRequest(Uri.parse('https://x.example.org/popunder/go.js'), page: page), isTrue);
      expect(blocksRequest(Uri.parse('https://www.mediafire.com/popunder/go.js'), page: page), isFalse);
    });
  });

  group('downloads', () {
    test('a package or archive in the path', () {
      expect(downloadFileName(Uri.parse('https://github.com/o/r/releases/download/v1/App_1.0.0.0_x64.msixbundle')), 'App_1.0.0.0_x64.msixbundle');
      expect(downloadFileName(Uri.parse('https://download1.mediafire.com/k/f/My%20App.zip')), 'My App.zip');
      expect(downloadFileName(Uri.parse('https://example.com/page.html')), isNull);
      expect(downloadFileName(Uri.parse('https://example.com/setup.exe')), isNull);
    });

    test('a file name hidden in a content-disposition query', () {
      final u = Uri.parse('https://objects.githubusercontent.com/x?response-content-disposition=attachment%3B%20filename%3DApp.msix&sig=1');
      expect(downloadFileName(u), 'App.msix');
    });
  });

  group('moving between pages', () {
    final from = Uri.parse('https://www.mediafire.com/file/abc');

    test('the same site and known file hosts are fine', () {
      expect(allowNavigation(from: from, to: Uri.parse('https://download1.mediafire.com/x/App.zip')), isTrue);
      expect(allowNavigation(from: from, to: Uri.parse('https://github.com/o/r/releases')), isTrue);
      expect(allowNavigation(from: from, to: Uri.parse('https://www.mediafire.com/other')), isTrue);
    });

    test('a redirect to an unknown site is stopped unless the user clicked', () {
      final ad = Uri.parse('https://lucky-prizes.example.xyz/win');
      expect(allowNavigation(from: from, to: ad), isFalse);
      expect(allowNavigation(from: from, to: ad, userGesture: true), isTrue);
    });

    test('ad hosts and app links never get through, even when clicked', () {
      expect(allowNavigation(from: from, to: Uri.parse('https://click.propellerads.com/x'), userGesture: true), isFalse);
      expect(allowNavigation(from: from, to: Uri.parse('intent://scan#Intent;end'), userGesture: true), isFalse);
      expect(allowNavigation(from: from, to: Uri.parse('market://details?id=x'), userGesture: true), isFalse);
    });

    test('registrable domains', () {
      expect(registrableDomain('download1.mediafire.com'), 'mediafire.com');
      expect(registrableDomain('a.b.example.co.uk'), 'example.co.uk');
      expect(registrableDomain('localhost'), 'localhost');
    });
  });
}
