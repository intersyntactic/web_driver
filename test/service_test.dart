import 'dart:convert';
import 'dart:io';

import 'package:is_effects/is_effects.dart';
import 'package:is_web_driver/service.dart';
import 'package:test/test.dart';

/// Answers every send with 201 and the request's path as what it made.
final class Echo implements WebDriver {
  final sent = <Request>[];

  @override
  Future<Outcome<Sent>> send(Request request) async {
    sent.add(request);
    return Ran(Sent(status: 201, created: request.path));
  }
}

final me = int.parse((Process.runSync('id', ['-u']).stdout as String).trim());
final api = Origin.parse('https://api.example')!;

void main() {
  late Directory dir;
  late File socket;
  late Echo driver;

  setUp(() async {
    // A Unix socket's path is short on macOS, so not under the test's own
    // temp directory.
    dir = await Directory('/tmp').createTemp('wd');
    socket = File('${dir.path}/s');
    driver = Echo();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<String> raw(String request) async {
    final s = await Socket.connect(
      InternetAddress(socket.path, type: InternetAddressType.unix),
      0,
    );
    s.add(utf8.encode(request));
    await s.close();
    return (await utf8.decoder.bind(s).join()).trim();
  }

  test('carries out a request from its caller, and answers it', () async {
    final service = await WebDriverService.start(driver, me, socket);
    addTearDown(service.close);
    final out = await SocketWebDriver(socket).send(
      Request(
        api,
        method: Method.post,
        path: '/v3/things',
        signIn: SignIn.parse('some-bot'),
        headers: {'content-type': 'application/json'},
        body: '{"a":1}',
      ),
    );
    final sent = (out as Ran<Sent>).output;
    expect(sent.status, 201);
    expect(sent.created, '/v3/things');
    final r = driver.sent.single;
    expect(r.origin, api);
    expect(r.method, Method.post);
    expect(r.signIn?.name, 'some-bot');
    expect(r.headers, {'content-type': 'application/json'});
    expect(r.body, '{"a":1}');
  });

  test('answers no one but its caller, and carries out nothing', () async {
    final service = await WebDriverService.start(driver, me + 1, socket);
    addTearDown(service.close);
    final out = await SocketWebDriver(socket).send(Request(api));
    expect(out, isA<Refused>());
    expect(driver.sent, isEmpty);
  });

  test('refuses a request carrying a credential', () async {
    final service = await WebDriverService.start(driver, me, socket);
    addTearDown(service.close);
    final answer = await raw(
      jsonEncode({
        'origin': 'https://api.example',
        'method': 'get',
        'path': '',
        'headers': {'Authorization': 'Bearer stolen'},
      }),
    );
    expect(answer, contains('refused'));
    expect(driver.sent, isEmpty);
  });

  test('refuses what is not a request', () async {
    final service = await WebDriverService.start(driver, me, socket);
    addTearDown(service.close);
    for (final bad in ['nope', '{}', '{"origin":"ftp://x","method":"get"}']) {
      expect(await raw(bad), contains('refused'));
    }
    expect(driver.sent, isEmpty);
  });

  test('says so when no service is listening', () async {
    expect(await SocketWebDriver(socket).send(Request(api)), isA<Refused>());
  });
}
