import 'dart:convert';
import 'dart:io';

import 'package:is_effects/is_effects.dart';
import 'package:is_web_driver/is_web_driver.dart';
import 'package:test/test.dart';

final teams = Origin.parse('https://smba.trafficmanager.net')!;
final hart = SignIn.parse('hart-bot')!;
final app = BotFrameworkApp(appId: 'app', tenantId: 'tenant', secret: 's3cret');

typedef Call = ({String method, Uri url, Map<String, String> headers});

void main() {
  late List<Call> calls;
  late DateTime clock;
  late String reply;

  SigningWebDriver driver() => SigningWebDriver(
    {hart: app},
    now: () => clock,
    http: (method, url, headers, body) async {
      calls.add((method: method, url: url, headers: headers));
      if (url.host == 'login.microsoftonline.com') {
        expect(body, contains('client_secret=s3cret'));
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

  Request post({
    SignIn? signIn,
    String path = '/amer/v3/conversations/c/activities',
  }) => Request(
    teams,
    method: Method.post,
    path: path,
    signIn: signIn,
    body: '{}',
  );

  setUp(() {
    calls = [];
    clock = DateTime.utc(2026, 11, 18);
    reply = '{"id":"1:abc"}';
  });

  test('signs with a Bot Connector token and reads the activity id', () async {
    final out = await driver().send(post(signIn: hart));
    final sent = (out as Ran<Sent>).output;
    expect(sent.status, 201);
    expect(sent.created, '1:abc');
    expect(calls.first.url.path, '/tenant/oauth2/v2.0/token');
    expect(
      calls.last.url.toString(),
      'https://smba.trafficmanager.net/amer/v3/conversations/c/activities',
    );
    expect(calls.last.headers['authorization'], 'Bearer tok1');
  });

  test('keeps a token until five minutes before it expires', () async {
    final d = driver();
    await d.send(post(signIn: hart));
    clock = clock.add(const Duration(minutes: 54));
    await d.send(post(signIn: hart));
    expect(
      calls.where((c) => c.url.host == 'login.microsoftonline.com'),
      hasLength(1),
    );
    clock = clock.add(const Duration(minutes: 2));
    await d.send(post(signIn: hart));
    expect(
      calls.where((c) => c.url.host == 'login.microsoftonline.com'),
      hasLength(2),
    );
  });

  test('concurrent sends share one token fetch', () async {
    final d = driver();
    await Future.wait([for (var i = 0; i < 5; i++) d.send(post(signIn: hart))]);
    expect(
      calls.where((c) => c.url.host == 'login.microsoftonline.com'),
      hasLength(1),
    );
  });

  test('never shows a sign-in to a site it is not for', () async {
    final other = Request(Origin.parse('https://example.com')!, signIn: hart);
    expect(await driver().send(other), isA<Refused>());
    expect(calls, isEmpty);
  });

  test('refuses a path that would name another site', () async {
    expect(
      await driver().send(post(signIn: hart, path: '@evil.example/x')),
      isA<Refused>(),
    );
    expect(
      await driver().send(post(signIn: hart, path: '.evil.example/x')),
      isA<Refused>(),
    );
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
      {},
      http: (_, _, _, _) async => (status: 403, body: '{"id":"x"}'),
    );
    final sent = ((await d.send(post())) as Ran<Sent>).output;
    expect(sent.status, 403);
    expect(sent.created, isNull);
  });

  test('a token the sign-in service refuses is a refusal', () async {
    final d = SigningWebDriver({
      hart: app,
    }, http: (_, _, _, _) async => (status: 401, body: '{}'));
    final out = await d.send(post(signIn: hart));
    expect((out as Refused).why, isNot(contains('s3cret')));
  });

  group('Credential', () {
    test('loads one file per sign-in', () async {
      final dir = await Directory.systemTemp.createTemp('creds');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/hart-bot').writeAsString(
        jsonEncode({
          'kind': 'bot-framework',
          'appId': 'a',
          'tenantId': 't',
          'secret': 's',
        }),
      );
      final loaded = await Credential.load(dir);
      expect(loaded[hart], isA<BotFrameworkApp>());
    });

    test('a bad file names the problem, never the secret', () {
      expect(
        () => Credential.parse('{"kind":"bot-framework","secret":"s3cret"}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            isNot(contains('s3cret')),
          ),
        ),
      );
    });
  });
}
