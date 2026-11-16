import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:is_effects/is_effects.dart';

import 'credential.dart';

typedef HttpResult = ({int status, String body});

/// Makes one HTTP call. Injected, so the driver is testable without a
/// network.
typedef HttpCall = Future<HttpResult> Function(
  String method,
  Uri url,
  Map<String, String> headers,
  String body,
);

/// A [WebDriver] that signs each request with the secret of the sign-in it
/// names, and only for the sites that sign-in is for.
final class SigningWebDriver implements WebDriver {
  SigningWebDriver(
    Map<SignIn, Credential> signIns, {
    HttpCall? http,
    DateTime Function()? now,
    void Function(String line)? log,
  }) : _signIns = Map.unmodifiable(signIns),
       _http = http ?? httpCall,
       _now = now ?? DateTime.now,
       _log = log ?? _silent;

  final Map<SignIn, Credential> _signIns;
  final HttpCall _http;
  final DateTime Function() _now;

  /// Where a refusal's reason goes when only its body says it: a non-2xx
  /// reply, or a token the sign-in service would not issue. For whoever runs
  /// the driver, not the record.
  final void Function(String line) _log;

  static void _silent(String _) {}

  /// Enough of a body to say why; an error page can run to megabytes.
  static String _clip(String body) =>
      body.length <= 2000 ? body : '${body.substring(0, 2000)}…';

  /// Shared by concurrent sends, so a burst asks for one token, not many.
  final _tokens = <SignIn, Future<_Token>>{};

  @override
  Future<Outcome<Sent>> send(Request request) async {
    final url = _url(request);
    if (url == null) return Refused('path ${request.path} leaves its origin');

    final signIn = request.signIn;
    final credential = signIn == null ? null : _signIns[signIn];
    if (signIn != null && credential == null) {
      return Refused('no sign-in $signIn');
    }
    // The airlock decides who may go where by name alone; only here is it
    // known that a secret would ride along to a site that never issued it.
    if (credential != null && !credential.origins.contains(request.origin)) {
      return Refused('$signIn is not for ${request.origin}');
    }

    final headers = {...request.headers};
    if (credential != null) {
      switch (await _authorization(signIn!, credential)) {
        case Ran(output: final value):
          headers['authorization'] = value;
        case final Refused refused:
          return refused;
      }
    }

    final HttpResult r;
    try {
      r = await _http(
        request.method.name.toUpperCase(),
        url,
        headers,
        request.body ?? '',
      );
    } on IOException catch (e) {
      return Refused('${request.origin}: $e');
    } on TimeoutException {
      return Refused('${request.origin}: timed out');
    }
    final ok = r.status >= 200 && r.status <= 299;
    if (!ok) {
      _log(
        '${request.method.name.toUpperCase()} $url '
        '${signIn == null ? '' : 'as $signIn '}${r.status}: ${_clip(r.body)}',
      );
    }
    return Ran(
      Sent(
        status: r.status,
        created: ok ? credential?.created?.read(r.body) : null,
        refusedBecause: ok
            ? null
            : _word(credential?.refusedBecause?.read(r.body)),
      ),
    );
  }

  Future<Outcome<String>> _authorization(
    SignIn signIn,
    Credential credential,
  ) async {
    switch (credential) {
      case ClientCredentials():
        final cached = _tokens[signIn];
        if (cached != null) {
          final token = await cached;
          if (_now().isBefore(token.until)) return Ran('Bearer ${token.value}');
          if (identical(_tokens[signIn], cached)) _tokens.remove(signIn);
        }
        final fetching = _tokens[signIn] ??= _clientCredentialsToken(
          credential,
        );
        try {
          return Ran('Bearer ${(await fetching).value}');
        } on _TokenRefused catch (e) {
          if (identical(_tokens[signIn], fetching)) _tokens.remove(signIn);
          return Refused('$signIn: $e');
        }
    }
  }

  /// Fetched again five minutes before it would expire, so a call never
  /// carries one that lapses in flight.
  Future<_Token> _clientCredentialsToken(ClientCredentials app) async {
    final HttpResult r;
    try {
      r = await _http('POST', app.tokenUrl, {
        'content-type': 'application/x-www-form-urlencoded',
      }, app.tokenForm);
    } on IOException catch (e) {
      throw _TokenRefused('token: $e');
    } on TimeoutException {
      throw _TokenRefused('token: timed out');
    }
    if (r.status != 200) {
      // A refusal's body is the service's error, never the token: a 200's
      // body is not logged, since that is where the token is.
      _log('token from ${app.tokenUrl.host} ${r.status}: ${_clip(r.body)}');
      final error = _word(_oauthError.read(r.body));
      throw _TokenRefused(
        'token: ${r.status}${error == null ? '' : ' $error'}',
      );
    }
    return switch (_json(r.body)) {
      {'access_token': final String value, 'expires_in': final int seconds} =>
        _Token(
          value,
          _now().add(Duration(seconds: seconds) - const Duration(minutes: 5)),
        ),
      _ => throw _TokenRefused('token: unreadable reply'),
    };
  }

  /// OAuth 2's error code (RFC 6749, 5.2), such as `invalid_client`: the
  /// protocol's own, so every token service gives it.
  static final _oauthError = ReplyField.parse('error')!;

  /// A reason short enough to keep for good; a field that holds more than a
  /// word or two was named by mistake.
  static String? _word(String? reason) => reason == null
      ? null
      : reason.length <= 200
      ? reason
      : '${reason.substring(0, 200)}…';

  /// [Request.path] appended to its origin, or null when the result names
  /// another site: `@evil.example` after `https://a.example` is a login to
  /// `evil.example`.
  static Uri? _url(Request request) {
    final path = request.path;
    if (path.isNotEmpty && !path.startsWith('/')) return null;
    final url = Uri.tryParse('${request.origin}$path');
    if (url == null || Origin.parse(url.origin) != request.origin) return null;
    return url;
  }

  static Object? _json(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

final class _Token {
  _Token(this.value, this.until);
  final String value;
  final DateTime until;
}

final class _TokenRefused implements Exception {
  _TokenRefused(this.why);
  final String why;

  @override
  String toString() => why;
}

/// [HttpCall] over `dart:io`, with a ten-second limit on each step.
Future<HttpResult> httpCall(
  String method,
  Uri url,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.openUrl(method, url);
    headers.forEach(req.headers.set);
    req.add(utf8.encode(body));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final text = await res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    return (status: res.statusCode, body: text);
  } finally {
    client.close();
  }
}
