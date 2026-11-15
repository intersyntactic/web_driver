/// The web driver as a service of its own, which only the airlock's user
/// may call. It runs as its own user, so a sign-in's secret is readable by
/// this process and no other: not the airlock, not another driver.
///
/// A caller connects to the Unix socket, sends one request (see
/// [encodeRequest]) and closes its side; the service answers one line, the
/// outcome (see [encodeOutcome]), and closes. [SocketWebDriver] is that
/// caller.
///
/// Who is calling is read from the socket as the kernel reports it, never
/// from the request.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:is_effects/is_effects.dart';

import 'src/wire.dart';

export 'src/wire.dart' show encodeOutcome, encodeRequest;

final class WebDriverService {
  WebDriverService._(this._driver, this._caller, this._socket, this._server);

  final WebDriver _driver;
  final int _caller;
  final File _socket;
  final ServerSocket _server;

  /// A request is a send's headers and body, so far smaller than this.
  static const maxRequest = 1 << 20;

  /// Listens on [socket], carrying out requests through [driver] for the
  /// user [caller] alone. A socket file nothing listens on is replaced.
  static Future<WebDriverService> start(
    WebDriver driver,
    int caller,
    File socket,
  ) async {
    final service = WebDriverService._(
      driver,
      caller,
      socket,
      await _bind(socket),
    );
    service._server.listen(service._serve);
    return service;
  }

  static Future<ServerSocket> _bind(File socket) async {
    final address = InternetAddress(
      socket.path,
      type: InternetAddressType.unix,
    );
    if (socket.existsSync()) {
      try {
        (await Socket.connect(address, 0)).destroy();
        throw StateError('a service is already listening on ${socket.path}');
      } on SocketException {
        socket.deleteSync();
      }
    }
    return ServerSocket.bind(address, 0);
  }

  Future<void> close() async {
    await _server.close();
    if (_socket.existsSync()) _socket.deleteSync();
  }

  Future<void> _serve(Socket socket) async {
    final uid = _peerUid(socket);
    try {
      if (uid != _caller) {
        socket.destroy();
        return;
      }
      final request = BytesBuilder(copy: false);
      var tooLarge = false;
      await for (final chunk in socket) {
        if (request.length + chunk.length > maxRequest) {
          tooLarge = true;
          break;
        }
        request.add(chunk);
      }
      final Outcome<Sent> outcome;
      if (tooLarge) {
        outcome = const Refused('request too large');
      } else {
        final decoded = decodeRequest(
          utf8.decode(request.takeBytes(), allowMalformed: true),
        );
        outcome = decoded is Request
            ? await _driver.send(decoded)
            : Refused('$decoded');
      }
      socket.add(utf8.encode('${encodeOutcome(outcome)}\n'));
      await socket.close();
    } on SocketException {
      socket.destroy();
    }
  }
}

/// A [WebDriver] in another process: sends each request to the service at
/// [socket]. Holds no secret.
final class SocketWebDriver implements WebDriver {
  SocketWebDriver(this.socket);

  final File socket;

  @override
  Future<Outcome<Sent>> send(Request request) async {
    try {
      final s = await Socket.connect(
        InternetAddress(socket.path, type: InternetAddressType.unix),
        0,
      );
      s.add(utf8.encode(encodeRequest(request)));
      await s.close();
      final answer = await utf8.decoder.bind(s).join();
      if (answer.isEmpty) return const Refused('web driver: refused caller');
      return decodeOutcome(answer.trim());
    } on SocketException catch (e) {
      return Refused('web driver: ${e.message}');
    }
  }
}

/// The user on the other end of [socket], as the kernel reports it: Linux's
/// `SO_PEERCRED`, macOS's `LOCAL_PEERCRED`. Null where neither is known.
/// The same as is_journal's writer reads its senders.
int? _peerUid(Socket socket) {
  try {
    if (Platform.isLinux) {
      final ucred = socket.getRawOption(RawSocketOption(1, 17, Uint8List(12)));
      return ByteData.sublistView(ucred).getUint32(4, Endian.host);
    }
    if (Platform.isMacOS) {
      final xucred = socket.getRawOption(RawSocketOption(0, 1, Uint8List(76)));
      return ByteData.sublistView(xucred).getUint32(4, Endian.host);
    }
  } on SocketException {
    return null;
  }
  return null;
}
