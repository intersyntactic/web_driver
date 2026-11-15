import 'dart:convert';
import 'dart:io';

import 'package:is_effects/is_effects.dart';
import 'package:is_web_driver/is_web_driver.dart';
import 'package:test/test.dart';

final api = Origin.parse('https://api.example')!;
final bot = SignIn.parse('some-bot')!;
final app = ClientCredentials(
  tokenUrl: Uri.parse('https://auth.example/token'),
  clientId: 'app',
  secret: 's3cret',
  scope: 'https://api.example/.default',
  origins: {api},
  created: 'id',
);

typedef Call = ({String method, Uri url, Map<String, String> headers});

void main() {
  late List<Call> calls;
  late DateTime clock;
  late String reply;

  Iterable<Call> tokenCalls() =>
      calls.where((c) => c.url.host == 'auth.example');

  SigningWebDriver driver() => SigningWebDriver(
    {bot: app},
    now: () => clock,
    http: (method, url, headers, body) async {
      calls.add((method: method, url: url, headers: headers));
      if (url.host == 'auth.example') {
        expect(body, contains('client_secret=s3cret'));
        expect(body, contains('grant_type=client_credentials'));
        return (
          status: 200,
          body: jsonEncode({
            'access_token': 'tok${calls.length}',
            'expires_in': 3600,
          }),
        );
      }
      return (status: 201, body: reply);
    },
  );

  Request post({SignIn? signIn, String path = '/v3/things'}) =>
      Request(api, method: Method.post, path: path, signIn: signIn, body: '{}');

  setUp(() {
    calls = [];
    clock = DateTime.utc(2026, 11, 18);
    reply = '{"id":"1:abc"}';
  });

  test('signs with a client-credentials token and reads created', () async {
    final out = await driver().send(post(signIn: bot));
    final sent = (out as Ran<Sent>).output;
    expect(sent.status, 201);
    expect(sent.created, '1:abc');
    expect(calls.last.url.toString(), 'https://api.example/v3/things');
    expect(calls.last.headers['authorization'], 'Bearer tok1');
  });

  test('keeps a token until five minutes before it expires', () async {
    final d = driver();
    await d.send(post(signIn: bot));
    clock = clock.add(const Duration(minutes: 54));
    await d.send(post(signIn: bot));
    expect(tokenCalls(), hasLength(1));
    clock = clock.add(const Duration(minutes: 2));
    await d.send(post(signIn: bot));
    expect(tokenCalls(), hasLength(2));
  });

  test('concurrent sends share one token fetch', () async {
    final d = driver();
    await Future.wait([for (var i = 0; i < 5; i++) d.send(post(signIn: bot))]);
    expect(tokenCalls(), hasLength(1));
  });

  test('never shows a sign-in to a site it is not for', () async {
    final other = Request(Origin.parse('https://example.com')!, signIn: bot);
    expect(await driver().send(other), isA<Refused>());
    expect(calls, isEmpty);
  });

  test('refuses a path that would name another site', () async {
    for (final path in ['@evil.example/x', '.evil.example/x']) {
      expect(
        await driver().send(post(signIn: bot, path: path)),
        isA<Refused>(),
      );
    }
    expect(calls, isEmpty);
  });

  test('refuses a sign-in it does not hold', () async {
    expect(
      await driver().send(post(signIn: SignIn.parse('nobody')!)),
      isA<Refused>(),
    );
    expect(calls, isEmpty);
  });

  test('sends under no sign-in without a credential', () async {
    final out = await driver().send(post());
    expect((out as Ran<Sent>).output.created, isNull);
    expect(calls.single.headers, isNot(contains('authorization')));
  });

  test('a refusal from the destination still ran, and made nothing', () async {
    final d = SigningWebDriver(
      {bot: app},
      now: () => clock,
      http: (_, url, _, _) async => url.host == 'auth.example'
          ? (status: 200, body: '{"access_token":"t","expires_in":3600}')
          : (status: 403, body: '{"id":"x"}'),
    );
    final sent = ((await d.send(post(signIn: bot))) as Ran<Sent>).output;
    expect(sent.status, 403);
    expect(sent.created, isNull);
  });

  test(
    'logs why the destination refused, which the outcome cannot carry',
    () async {
      final log = <String>[];
      final d = SigningWebDriver(
        {bot: app},
        now: () => clock,
        log: log.add,
        http: (_, url, _, _) async => url.host == 'auth.example'
            ? (status: 200, body: '{"access_token":"t0ken","expires_in":3600}')
            : (status: 404, body: '{"error":"ConversationNotFound"}'),
      );
      await d.send(post(signIn: bot));
      expect(log.single, contains('404'));
      expect(log.single, contains('ConversationNotFound'));
      expect(log.single, isNot(contains('t0ken')));
    },
  );

  test('logs why a token was refused, never the secret', () async {
    final log = <String>[];
    final d = SigningWebDriver(
      {bot: app},
      log: log.add,
      http: (_, _, _, _) async => (
        status: 401,
        body: '{"error":"invalid_client","error_codes":[7000215]}',
      ),
    );
    await d.send(post(signIn: bot));
    expect(log.single, contains('7000215'));
    expect(log.single, isNot(contains('s3cret')));
  });

  test('logs nothing when a send succeeds', () async {
    final log = <String>[];
    final d = SigningWebDriver(
      {bot: app},
      now: () => clock,
      log: log.add,
      http: (_, url, _, _) async => url.host == 'auth.example'
          ? (status: 200, body: '{"access_token":"t0ken","expires_in":3600}')
          : (status: 201, body: '{"id":"1"}'),
    );
    await d.send(post(signIn: bot));
    expect(log, isEmpty);
  });

  test('a token the sign-in service refuses is a refusal', () async {
    final d = SigningWebDriver({
      bot: app,
    }, http: (_, _, _, _) async => (status: 401, body: '{}'));
    final out = await d.send(post(signIn: bot));
    expect((out as Refused).why, isNot(contains('s3cret')));
  });

  group('Credential', () {
    final file = {
      'kind': 'client-credentials',
      'tokenUrl': 'https://auth.example/token',
      'clientId': 'a',
      'secret': 's3cret',
      'origins': ['https://api.example'],
      'created': 'id',
    };

    test('loads one file per sign-in', () async {
      final dir = await Directory.systemTemp.createTemp('creds');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/some-bot').writeAsString(jsonEncode(file));
      final loaded = await Credential.load(dir);
      expect(loaded[bot]?.origins, {api});
      expect(loaded[bot]?.created, 'id');
    });

    for (final (why, broken) in [
      ('no secret', {...file}..remove('secret')),
      ('no origins', {...file, 'origins': <String>[]}),
      (
        'an origin with a path',
        {
          ...file,
          'origins': ['https://a.example/x'],
        },
      ),
      ('a token url in the clear', {...file, 'tokenUrl': 'http://a.example'}),
    ]) {
      test('refuses $why, never naming the secret', () {
        expect(
          () => Credential.parse(jsonEncode(broken)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              isNot(contains('s3cret')),
            ),
          ),
        );
      });
    }
  });
}
