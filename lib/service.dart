/// The web request driver as a service of its own, which only the airlock's user
/// may call. It runs as its own user, so a sign-in's secret is readable by
/// this process and no other: not the airlock, not another driver.
///
/// A caller connects to the Unix socket, writes one [Request] in is_effects'
/// JSON ([encodeRequest]) and closes its side; the service answers one line,
/// the `Outcome<WebResponse>` ([encodeOutcome]), and closes.
/// [WebRequestDriverSocket] is that caller.
///
/// Who is calling is read from the socket as the kernel reports it, never
/// from the request.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:is_effects/is_effects.dart';
import 'package:is_unix_socket_user_check/is_unix_socket_user_check.dart';

export 'package:is_unix_socket_user_check/is_unix_socket_user_check.dart'
    show UserId;

final class WebRequestDriverService {
  WebRequestDriverService._(
    this._driver,
    this._socketUserCheck,
    this._socket,
    this._server,
  );

  final CarriesOutWebRequests _driver;
  final SocketUserCheck _socketUserCheck;
  final File _socket;
  final ServerSocket _server;

  /// A request is a web request's headers and body, so far smaller than this.
  static const maxRequest = 1 << 20;

  /// Listens on [socket], carrying out requests through [driver] for the
  /// user [caller] alone. A socket file nothing listens on is replaced.
  static Future<WebRequestDriverService> start(
    CarriesOutWebRequests driver,
    UserId caller,
    File socket,
  ) async {
    final service = WebRequestDriverService._(
      driver,
      SocketUserCheck.only(caller),
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
    try {
      if (!_socketUserCheck.allows(socket)) {
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
      final Outcome<WebResponse> outcome;
      if (tooLarge) {
        outcome = const Refused('request too large');
      } else {
        final Request decoded;
        try {
          decoded = decodeRequest(
            jsonDecode(utf8.decode(request.takeBytes(), allowMalformed: true)),
          );
        } on FormatException catch (e) {
          await _answer(socket, Refused('not a request: ${e.message}'));
          return;
        }
        outcome = await _driver.carryOutWebRequest(decoded);
      }
      await _answer(socket, outcome);
    } on SocketException {
      socket.destroy();
    }
  }

  static Future<void> _answer(
    Socket socket,
    Outcome<WebResponse> outcome,
  ) async {
    try {
      socket.add(
        utf8.encode(
          '${jsonEncode(encodeOutcome(outcome, encodeWebResponse))}\n',
        ),
      );
      await socket.close();
    } on SocketException {
      socket.destroy();
    }
  }
}

/// Looks at the driver on the other end of a connected socket, such as which
/// release the kernel says it is, before any request is written to it.
/// Returns why to refuse it, or null to go on.
typedef CheckDriver = Future<String?> Function(Socket driver);

/// [CarriesOutWebRequests] in another process: passes each request to the service at
/// [socket]. Holds no secret.
final class WebRequestDriverSocket implements CarriesOutWebRequests {
  /// [checkDriver] runs on every connection before the request is sent, so
  /// a driver it refuses never sees the request.
  WebRequestDriverSocket(this.socket, {this.checkDriver});

  final File socket;
  final CheckDriver? checkDriver;

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(Request request) async {
    try {
      final s = await Socket.connect(
        InternetAddress(socket.path, type: InternetAddressType.unix),
        0,
      );
      if (await checkDriver?.call(s) case final why?) {
        s.destroy();
        return Refused('web request driver: $why');
      }
      s.add(utf8.encode(jsonEncode(encodeRequest(request))));
      await s.close();
      final answer = await utf8.decoder.bind(s).join();
      if (answer.isEmpty) {
        return const Refused('web request driver: refused caller');
      }
      return decodeOutcome(jsonDecode(answer), decodeWebResponse);
    } on SocketException catch (e) {
      return Refused('web request driver: ${e.message}');
    } on FormatException catch (e) {
      return Refused('web request driver: unreadable answer: ${e.message}');
    }
  }
}
