import 'dart:convert';

import 'package:is_effects/is_effects.dart';

/// A [Request] as the service's socket carries it: one JSON object.
String encodeRequest(Request r) => jsonEncode({
  'origin': r.origin.toString(),
  'method': r.method.name,
  'path': r.path,
  'signIn': r.signIn?.name,
  'headers': r.headers,
  'body': r.body,
});

/// The [Request] in [raw], or why it is not one. Checks what [Request]'s
/// constructor would throw on, since the socket is not to be trusted to have
/// gone through it.
Object decodeRequest(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return 'not JSON';
  }
  if (json case {
    'origin': final String origin,
    'method': final String method,
    'path': final String path,
    'headers': final Map<String, Object?> headers,
  }) {
    final o = Origin.parse(origin);
    if (o == null) return 'not an origin: $origin';
    final m = Method.values.asNameMap()[method];
    if (m == null) return 'not a method: $method';
    final SignIn? signIn;
    switch (json['signIn']) {
      case null:
        signIn = null;
      case final String name:
        signIn = SignIn.parse(name);
        if (signIn == null) return 'not a sign-in: $name';
      default:
        return 'sign-in is not text';
    }
    final h = <String, String>{};
    for (final MapEntry(:key, :value) in headers.entries) {
      if (value is! String) return 'header $key is not text';
      if (_credentialHeaders.contains(key.toLowerCase())) {
        return "header $key carries a credential, which is the sign-in's";
      }
      h[key] = value;
    }
    final body = json['body'];
    if (body != null && body is! String) return 'body is not text';
    return Request(
      o,
      method: m,
      path: path,
      signIn: signIn,
      headers: h,
      body: body as String?,
    );
  }
  return 'not a request';
}

/// The same names [Request] refuses.
const _credentialHeaders = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'x-api-key',
};

String encodeOutcome(Outcome<Sent> o) => jsonEncode(switch (o) {
  Ran(output: Sent(:final status, :final created)) => {
    'ran': {'status': status, 'created': created},
  },
  Refused(:final why) => {'refused': why},
});

Outcome<Sent> decodeOutcome(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return Refused('web driver: unreadable answer');
  }
  return switch (json) {
    {'ran': {'status': final int status, 'created': final String? created}} =>
      Ran(Sent(status: status, created: created)),
    {'refused': final String why} => Refused(why),
    _ => Refused('web driver: unreadable answer'),
  };
}
