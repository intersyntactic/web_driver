import 'dart:convert';
import 'dart:io';

import 'package:is_effects/is_effects.dart';

/// A sign-in's secret, how it is shown, and where. Each kind is a way of
/// proving who you are, never a destination: what a destination is lives in
/// the sign-in's file, not in this package.
sealed class Credential {
  Credential({required this.origins, this.created});

  /// The only sites this sign-in is ever shown to.
  final Set<Origin> origins;

  /// The field of a 2xx reply's JSON object that names what the destination
  /// made, such as `id`; null when it makes nothing worth recording.
  final String? created;

  /// [raw], a sign-in's credential file, or a [FormatException] naming what
  /// is wrong with it but never its secret.
  static Credential parse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('credential is not JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('credential is not a JSON object');
    }
    final origins = switch (json['origins']) {
      final List<Object?> list when list.isNotEmpty => {
        for (final o in list)
          (o is String ? Origin.parse(o) : null) ??
              (throw FormatException('not an origin: $o')),
      },
      _ => throw const FormatException('credential names no origins'),
    };
    final created = switch (json['created']) {
      null => null,
      final String field when field.isNotEmpty => field,
      _ => throw const FormatException('created is not a field name'),
    };
    return switch (json) {
      {
        'kind': 'client-credentials',
        'tokenUrl': final String tokenUrl,
        'clientId': final String clientId,
        'secret': final String secret,
      }
          when clientId.isNotEmpty && secret.isNotEmpty =>
        ClientCredentials(
          tokenUrl: _https(tokenUrl),
          clientId: clientId,
          secret: secret,
          scope: switch (json['scope']) {
            null => null,
            final String scope => scope,
            _ => throw const FormatException('scope is not text'),
          },
          origins: origins,
          created: created,
        ),
      {'kind': final String kind} => throw FormatException(
        'not a complete $kind credential',
      ),
      _ => throw const FormatException('credential names no kind'),
    };
  }

  /// Every file in [directory], each a credential named for its sign-in:
  /// what systemd's LoadCredential leaves in `$CREDENTIALS_DIRECTORY`.
  static Future<Map<SignIn, Credential>> load(Directory directory) async {
    final loaded = <SignIn, Credential>{};
    await for (final file in directory.list()) {
      if (file is! File) continue;
      final name = file.uri.pathSegments.last;
      final signIn =
          SignIn.parse(name) ??
          (throw FormatException('not a sign-in name', name));
      try {
        loaded[signIn] = parse(await file.readAsString());
      } on FormatException catch (e) {
        throw FormatException('$signIn: ${e.message}');
      }
    }
    return loaded;
  }

  /// The secret travels to it, so never in the clear.
  static Uri _https(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw FormatException('not an https url: $raw');
    }
    return uri;
  }
}

/// OAuth 2's client-credentials grant: trades a client id and secret at
/// [tokenUrl] for a bearer token, kept until shortly before it expires.
final class ClientCredentials extends Credential {
  ClientCredentials({
    required this.tokenUrl,
    required this.clientId,
    required this._secret,
    this.scope,
    required super.origins,
    super.created,
  });

  final Uri tokenUrl;
  final String clientId;
  final String _secret;
  final String? scope;

  String get tokenForm => Uri(
    queryParameters: {
      'grant_type': 'client_credentials',
      'client_id': clientId,
      'client_secret': _secret,
      'scope': ?scope,
    },
  ).query;
}
