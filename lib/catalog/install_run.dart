import 'dart:io';

import 'package:koni_archive/io.dart';
import 'package:flutter/foundation.dart';

import '../portal/install_plan.dart';
import '../portal/package_info.dart';
import '../portal/portal_client.dart';
import '../state/console_session.dart';
import '../ui/errors.dart';
import 'catalog_client.dart';
import 'models.dart';
import 'sources/link_resolver.dart';

enum StepStatus { pending, active, done, skipped, failed }

class RunStep {
  RunStep(this.title);

  final String title;
  StepStatus state = StepStatus.pending;

  // one line under the title, like 120 of 438 MB
  String detail = '';

  // null while the size is not known
  double? fraction;
}

String megabytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.toStringAsFixed(0)} MB';
}

// each step reports on its own so the screen can say exactly where it is
class InstallRun extends ChangeNotifier {
  InstallRun({required this.app, required this.catalog, required this.session, this.onInstalled});

  CatalogApp app;
  final CatalogClient catalog;
  final ConsoleSession session;

  // lets the app remember which installed package this catalogue entry became
  final void Function(CatalogApp app, PackageInfo info)? onInstalled;

  final steps = [RunStep('Download'), RunStep('Check'), RunStep('Send to console'), RunStep('Install')];
  final _cancel = CancelToken();

  bool started = false;
  bool finished = false;
  String? error;
  InstalledPackage? result;

  // true when this went over an older copy, so its saved data was kept
  bool updated = false;

  bool get running => started && !finished;
  bool get failed => error != null;

  void _set(RunStep s, StepStatus state, {String? detail, double? fraction, bool keepFraction = false}) {
    s.state = state;
    if (detail != null) s.detail = detail;
    if (!keepFraction) s.fraction = fraction;
    notifyListeners();
  }

  void cancel() => _cancel.cancel();

  Future<void> start() async {
    if (started) return;
    started = true;
    notifyListeners();

    final temp = await Directory.systemTemp.createTemp('portalapp_');
    var current = steps.first;
    try {
      if (app.needsResolving) {
        current = steps[0];
        _set(current, StepStatus.active, detail: 'Finding the download', fraction: null);
        app = await LinkResolver(catalog.text).resolve(app);
      }
      final main = app.mainPackage;
      final archive = app.archive;
      if (main == null && archive == null) throw PortalException('${app.name} has no package to install.');

      // download
      current = steps[0];
      final files = <File>[];
      _set(current, StepStatus.active, detail: 'Starting', fraction: null);
      final wanted = main == null ? [archive!] : [main, ...app.dependencies];
      for (var i = 0; i < wanted.length; i++) {
        final d = wanted[i];
        final label = wanted.length == 1 ? d.name : '${d.name} (${i + 1} of ${wanted.length})';
        files.add(await catalog.download(
          app.resolve(d),
          File('${temp.path}${Platform.pathSeparator}${d.name}'),
          cancel: _cancel,
          onProgress: (got, total) {
            _set(current, StepStatus.active,
                detail: total > 0 ? '$label, ${megabytes(got)} of ${megabytes(total)}' : '$label, ${megabytes(got)}',
                fraction: total > 0 ? got / total : null);
          },
        ));
      }
      if (main == null) {
        _set(current, StepStatus.active, detail: 'Unpacking ${archive!.name}', fraction: null);
        final unpacked = await unpackPackages(files.first, Directory('${temp.path}${Platform.pathSeparator}unpacked'));
        files
          ..clear()
          ..addAll(unpacked);
      }
      _set(current, StepStatus.done, detail: files.length == 1 ? files.first.uri.pathSegments.last : '${files.length} files');

      // check
      current = steps[1];
      _set(current, StepStatus.active, detail: 'Reading the package');
      final info = await readPackageInfo(files.first);
      final plan = planInstall(info, await session.client.packages());
      if (!plan.allowed) throw PortalException('${app.name} is not signed, so the console would refuse it.');
      updated = plan.kind == InstallKind.update;
      final sum = app.checksum;
      if (sum == null) {
        _set(current, StepStatus.done, detail: 'Signed. The catalogue lists no checksum for this one.');
      } else {
        _set(current, StepStatus.active, detail: 'Checking the SHA-256');
        final expected = await catalog.checksumFor(app, sum);
        final actual = await sha256Of(files.first);
        if (expected != actual) {
          throw PortalException('The download does not match its published checksum, so it was not installed. '
              'Try again, and tell the developer if it keeps happening.');
        }
        _set(current, StepStatus.done, detail: 'Signed, and the checksum matches');
      }

      // send and install share one call, the upload callback tells them apart
      current = steps[2];
      final upgrade = plan.kind == InstallKind.update ? 'Updating from ${plan.installed!.version}' : 'Sending';
      _set(current, StepStatus.active, detail: upgrade, fraction: 0);
      final installed = await session.install(
        info,
        dependencies: files.skip(1).toList(),
        onUpload: (sent, total) {
          if (total <= 0) return;
          if (sent >= total) {
            if (steps[2].state != StepStatus.done) {
              _set(steps[2], StepStatus.done, detail: megabytes(total));
              current = steps[3];
              _set(current, StepStatus.active, detail: 'The console is installing it', fraction: null);
            }
          } else {
            _set(steps[2], StepStatus.active, detail: '${megabytes(sent)} of ${megabytes(total)}', fraction: sent / total);
          }
        },
      );
      if (steps[3].state != StepStatus.done) _set(steps[3], StepStatus.done, detail: '${installed.name} ${installed.version}');
      onInstalled?.call(app, info);
      result = installed;
      finished = true;
      notifyListeners();
    } catch (e) {
      error = e is CancelledException ? 'Cancelled. Nothing was installed.' : friendlyError(e, address: session.address);
      _set(current, StepStatus.failed);
      finished = true;
      notifyListeners();
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    }
  }
}

bool _isPackage(String path) {
  final lower = path.toLowerCase();
  return packageExtensions.any((e) => lower.endsWith('.$e'));
}

Future<List<File>> unpackPackages(File zip, Directory into) async {
  await into.create(recursive: true);
  final found = <File>[];
  final archive = await openArchiveFile(zip.path);
  try {
    for (final entry in archive.entries) {
      if (entry.type != ArchiveEntryType.file || !_isPackage(entry.path)) continue;
      final folder = await Directory('${into.path}${Platform.pathSeparator}${found.length}').create();
      final out = File('${folder.path}${Platform.pathSeparator}${entry.path.split('/').last}');
      final sink = out.openWrite();
      try {
        await sink.addStream(archive.openRead(entry));
      } finally {
        await sink.close();
      }
      found.add(out);
    }
  } finally {
    await archive.close();
  }
  if (found.isEmpty) throw PortalException('There is no app package inside ${zip.uri.pathSegments.last}.');

  final infos = <PackageInfo>[];
  for (final f in found) {
    infos.add(await readPackageInfo(f));
  }
  bool framework(PackageInfo i) => i.name.toLowerCase().startsWith('microsoft.');
  final apps = [for (final i in infos) if (!framework(i)) i]
    ..sort((a, b) {
      final da = a.fileName.toLowerCase().contains('debug') ? 1 : 0;
      final db = b.fileName.toLowerCase().contains('debug') ? 1 : 0;
      return da != db ? da - db : a.fileName.compareTo(b.fileName);
    });
  if (apps.isEmpty) throw PortalException('There is no app package inside ${zip.uri.pathSegments.last}.');
  return [apps.first.file, for (final i in infos) if (framework(i)) i.file];
}
