import 'dart:convert';
import 'dart:io';

import 'package:is_effects/is_effects.dart';

/// A sign-in's secret, and the sites it may be shown to. Each kind proves
/// who it is in its own way and reads what its destination made in its own
/// way.
sealed class Credential {
  const Credential();

  Set<Origin> get origins;

  /// [raw], a sign-in's credential file, or a [FormatException] naming what
  /// is wrong with it but never its secret.
  static Credential parse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('credential is not JSON');
    }
    return switch (json) {
      {
        'kind': 'bot-framework',
        'appId': final String appId,
        'tenantId': final String tenantId,
        'secret': final String secret,
      }
          when appId.isNotEmpty && tenantId.isNotEmpty && secret.isNotEmpty =>
        BotFrameworkApp(appId: appId, tenantId: tenantId, secret: secret),
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
}

/// A Teams bot's app registration. It signs with a Bot Connector token from
/// Microsoft's sign-in service, and what it made is the activity whose id
/// comes back in the reply.
final class BotFrameworkApp extends Credential {
  BotFrameworkApp({
    required this.appId,
    required this.tenantId,
    required this._secret,
  });

  final String appId;

  /// A single-tenant bot's token comes from its own tenant.
  final String tenantId;

  final String _secret;

  @override
  Set<Origin> get origins => {Origin.parse('https://smba.trafficmanager.net')!};

  static const scope = 'https://api.botframework.com/.default';

  Uri get tokenUrl => Uri.https(
    'login.microsoftonline.com',
    '/${Uri.encodeComponent(tenantId)}/oauth2/v2.0/token',
  );

  String get tokenForm => Uri(
    queryParameters: {
      'grant_type': 'client_credentials',
      'client_id': appId,
      'client_secret': _secret,
      'scope': scope,
    },
  ).query;
}
