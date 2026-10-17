const _adHosts = {
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'adservice.google.com',
  'google-analytics.com',
  'googletagmanager.com',
  'googletagservices.com',
  'adnxs.com',
  'taboola.com',
  'outbrain.com',
  'popads.net',
  'popcash.net',
  'propellerads.com',
  'propellerclick.com',
  'exoclick.com',
  'exosrv.com',
  'juicyads.com',
  'trafficjunky.com',
  'adsterra.com',
  'hilltopads.net',
  'clickadu.com',
  'adcash.com',
  'mgid.com',
  'revcontent.com',
  'criteo.com',
  'criteo.net',
  'pubmatic.com',
  'rubiconproject.com',
  'openx.net',
  'casalemedia.com',
  'amazon-adsystem.com',
  'scorecardresearch.com',
  'quantserve.com',
  'moatads.com',
  'adsrvr.org',
  'bidswitch.net',
  'smartadserver.com',
  'advertising.com',
  'adform.net',
  'yieldmo.com',
  'onetag-sys.com',
  '33across.com',
  'sharethrough.com',
  'zedo.com',
  'adskeeper.com',
  'ad-maven.com',
  'admaven.com',
  'a-ads.com',
  'bidvertiser.com',
  'infolinks.com',
  'media.net',
  'monetag.com',
  'richpartners.com',
  'syndication.exoclick.com',
  'tsyndicate.com',
  'ero-advertising.com',
  'mc.yandex.ru',
  'an.yandex.ru',
  'hotjar.com',
  'facebook.net',
  'serving-sys.com',
  'yahoo-adservice.com',
  'zemanta.com',
  'cpmstar.com',
  'sponsorpay.com',
  'trk.ad',
};

final _adPaths = RegExp(r'/(pagead|adserver|ad-server|popunder|popads|adsbygoogle|doubleclick)(/|\.|$)', caseSensitive: false);

const _packageExtensions = ['msix', 'appx', 'msixbundle', 'appxbundle', 'zip', '7z'];

const _trustedHosts = {
  'github.com',
  'githubusercontent.com',
  'mediafire.com',
  'sourceforge.net',
  'gitlab.com',
  'codeberg.org',
  'itch.io',
  'itch.zone',
  'archive.org',
  'dropbox.com',
  'dropboxusercontent.com',
  'mega.nz',
  'gofile.io',
  'drive.google.com',
  'googleusercontent.com',
  'onedrive.live.com',
  '1drv.ms',
};

final _doubleSuffix = {'co', 'com', 'org', 'net', 'gov', 'ac', 'edu'};

String registrableDomain(String host) {
  final labels = host.toLowerCase().split('.');
  if (labels.length <= 2) return host.toLowerCase();
  final last = labels.last;
  if (last.length == 2 && _doubleSuffix.contains(labels[labels.length - 2])) return labels.sublist(labels.length - 3).join('.');
  return labels.sublist(labels.length - 2).join('.');
}

bool _hostIn(Set<String> set, String host) {
  final h = host.toLowerCase();
  for (final entry in set) {
    if (h == entry || h.endsWith('.$entry')) return true;
  }
  return false;
}

bool isAdHost(String host) => _hostIn(_adHosts, host);

bool isTrustedHost(String host) => _hostIn(_trustedHosts, host);

bool blocksRequest(Uri url, {required Uri page}) {
  if (isAdHost(url.host)) return true;
  final thirdParty = registrableDomain(url.host) != registrableDomain(page.host);
  return thirdParty && _adPaths.hasMatch(url.path);
}

String? downloadFileName(Uri url) {
  String? fromPath(String path) {
    final name = Uri.decodeComponent(path.split('/').last);
    final lower = name.toLowerCase();
    return _packageExtensions.any((e) => lower.endsWith('.$e')) ? name : null;
  }

  final direct = fromPath(url.path);
  if (direct != null) return direct;
  for (final key in ['response-content-disposition', 'filename', 'file', 'name']) {
    final value = url.queryParameters[key];
    if (value == null) continue;
    final match = RegExp(r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?', caseSensitive: false).firstMatch(value);
    final hit = fromPath(match?.group(1) ?? value);
    if (hit != null) return hit;
  }
  return null;
}

bool allowNavigation({required Uri from, required Uri to, bool userGesture = false}) {
  if (to.scheme != 'http' && to.scheme != 'https') return to.scheme == 'about';
  if (isAdHost(to.host)) return false;
  if (downloadFileName(to) != null) return true;
  if (registrableDomain(from.host) == registrableDomain(to.host)) return true;
  if (isTrustedHost(to.host)) return true;
  return userGesture;
}

bool isInstallableName(String name) {
  final lower = name.toLowerCase();
  return _packageExtensions.any((e) => lower.endsWith('.$e'));
}
