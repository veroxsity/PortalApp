import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:portal_app/browser/browser_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the browser blocks the ad and the popup and hands over the package', (tester) async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final served = <String>[];
    server.listen((req) {
      served.add(req.uri.path);
      if (req.uri.path == '/') {
        req.response.headers.contentType = ContentType.html;
        req.response.write('''<html><body><h1>Download page</h1>
<script src="http://localhost:PORT/popunder/ad.js"></script>
<script src="https://ads.doubleclick.net/ad.js"></script>
<img src="http://localhost:PORT/pixel.png">
<script>
  window.open('http://localhost:PORT/popup', '_blank');
  window.addEventListener('load', function () { setTimeout(function () { document.getElementById('dl').click(); }, 800); });
</script>
<a id="dl" href="/files/Game_1.0.0.0_x64.msix">Download</a></body></html>'''.replaceAll('PORT', '${server.port}'));
      } else {
        req.response.add(List.filled(16, 0));
      }
      req.response.close();
    });

    final start = Uri.parse('http://127.0.0.1:${server.port}/');
    BrowserDownload? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => got = await BrowserPage.open(context, start),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();

    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (got == null && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await server.close(force: true);

    expect(got, isNotNull, reason: 'nothing was captured; served: $served');
    expect(got!.name, 'Game_1.0.0.0_x64.msix');
    expect(got!.url.path, '/files/Game_1.0.0.0_x64.msix');
    expect(served, isNot(contains('/popunder/ad.js')), reason: 'the ad script was fetched');
    expect(served, isNot(contains('/popup')), reason: 'the popup opened');
    expect(served, contains('/pixel.png'), reason: 'an ordinary image should still load');
  });
}
