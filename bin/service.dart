/// Runs the web driver as a service (see `package:is_web_driver/service.dart`):
///
///     WEB_DRIVER_SOCKET=/run/intersyntactic-web-driver/web-driver.sock \
///       WEB_DRIVER_CALLER=airlock \
///       CREDENTIALS_DIRECTORY=... \
///       dart run is_web_driver:service
///
/// `WEB_DRIVER_CALLER` is the one user, by name or id, whose requests it
/// carries out. systemd sets `CREDENTIALS_DIRECTORY` from `LoadCredential=`.
///
/// Exits 78 when it cannot start as configured, and closes cleanly on
/// SIGTERM or SIGINT.
library;

import 'dart:async';
import 'dart:io';

import 'package:is_effects/is_effects.dart';
import 'package:is_web_driver/is_web_driver.dart';
import 'package:is_web_driver/service.dart';

Future<void> main() async {
  final env = Platform.environment;
  final [socket, caller, credentials] = [
    for (final name in [
      'WEB_DRIVER_SOCKET',
      'WEB_DRIVER_CALLER',
      'CREDENTIALS_DIRECTORY',
    ])
      env[name] ?? _fail('$name is not set'),
  ];
  final uid = _uidOf(caller) ?? _fail('no user $caller');
  final Map<SignIn, Credential> signIns;
  try {
    signIns = await Credential.load(Directory(credentials));
  } on Exception catch (e) {
    _fail('$e');
  }
  final WebDriverService service;
  try {
    service = await WebDriverService.start(
      SigningWebDriver(signIns, log: stdout.writeln),
      uid,
      File(socket),
    );
  } on Object catch (e) {
    _fail('$e');
  }
  stdout.writeln(
    'listening on $socket for $caller, '
    'sign-ins: ${signIns.keys.join(' ')}',
  );
  final stop = Completer<void>();
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  await service.close();
  exit(0);
}

int? _uidOf(String user) {
  if (int.tryParse(user) case final uid?) return uid;
  final r = Process.runSync('id', ['-u', user]);
  return r.exitCode == 0 ? int.tryParse(r.stdout.toString().trim()) : null;
}

Never _fail(String why) {
  stderr.writeln('is_web_driver service: $why');
  exit(78);
}
