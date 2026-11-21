import 'dart:convert';
import 'dart:io';

import 'package:is_effects/is_effects.dart';
import 'package:is_web_request_driver/service.dart';
import 'package:test/test.dart';

/// Answers every send with 201 and the request's path as what it made.
final class Echo implements CarriesOutWebRequests {
  final sent = <Request>[];

  @override
  Future<Outcome<WebResponse>> carryOutWebRequest(Request request) async {
    sent.add(request);
    if (request.path.value == '/refuse') {
      return Ran(WebResponse(status: 400, refusedBecause: 'BadArgument'));
    }
    return Ran(WebResponse(status: 201, created: request.path.value));
  }
}

final myUid = int.parse(
  (Process.runSync('id', ['-u']).stdout as String).trim(),
);
final me = UserId.parse(myUid)!;
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
    final service = await WebRequestDriverService.start(driver, me, socket);
    addTearDown(service.close);
    final out = await WebRequestDriverSocket(socket).carryOutWebRequest(
      Request(
        api,
        method: Method.post,
        path: WebPath.parse('/v3/things')!,
        signIn: SignIn.parse('some-bot'),
        headers: {'content-type': 'application/json'},
        body: '{"a":1}',
      ),
    );
    final sent = (out as Ran<WebResponse>).output;
    expect(sent.status, 201);
    expect(sent.created, '/v3/things');
    expect(sent.refusedBecause, isNull);
    final r = driver.sent.single;
    expect(r.origin, api);
    expect(r.method, Method.post);
    expect(r.signIn?.name, 'some-bot');
    expect(r.headers, {'content-type': 'application/json'});
    expect(r.body, '{"a":1}');
  });

  test('carries why a destination refused back across the socket', () async {
    final service = await WebRequestDriverService.start(driver, me, socket);
    addTearDown(service.close);
    final out = await WebRequestDriverSocket(socket)
        .carryOutWebRequest(Request(api, path: WebPath.parse('/refuse')!));
    final sent = (out as Ran<WebResponse>).output;
    expect(sent.status, 400);
    expect(sent.refusedBecause, 'BadArgument');
  });

  // The answer from a driver before is_effects' wire format: never guessed
  // at, so a driver and airlock deployed out of step fail loudly.
  test('an answer it cannot read is a refusal', () async {
    final server = await ServerSocket.bind(
      InternetAddress(socket.path, type: InternetAddressType.unix),
      0,
    );
    addTearDown(server.close);
    server.listen((s) async {
      await s.drain<void>();
      s.write('{"ran":{"status":201,"created":"1:abc"}}\n');
      await s.close();
    });
    final out = await WebRequestDriverSocket(socket)
        .carryOutWebRequest(Request(api));
    expect((out as Refused).why, contains('unreadable answer'));
  });

  test('answers no one but its caller, and carries out nothing', () async {
    final service = await WebRequestDriverService.start(
      driver,
      UserId.parse(myUid + 1)!,
      socket,
    );
    addTearDown(service.close);
    final out = await WebRequestDriverSocket(socket)
        .carryOutWebRequest(Request(api));
    expect(out, isA<Refused>());
    expect(driver.sent, isEmpty);
  });

  test('refuses a request carrying a credential', () async {
    final service = await WebRequestDriverService.start(driver, me, socket);
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
    final service = await WebRequestDriverService.start(driver, me, socket);
    addTearDown(service.close);
    for (final bad in ['nope', '{}', '{"origin":"ftp://x","method":"get"}']) {
      expect(await raw(bad), contains('refused'));
    }
    expect(driver.sent, isEmpty);
  });

  // A path cannot be built that names another site, but the socket carries
  // text, which never went through WebPath.
  test('refuses a path that would name another site', () async {
    final service = await WebRequestDriverService.start(driver, me, socket);
    addTearDown(service.close);
    for (final path in ['@evil.example/x', '//evil.example/x', '/a/../b']) {
      final answer = await raw(
        jsonEncode({
          'origin': 'https://api.example',
          'method': 'get',
          'path': path,
          'signIn': 'some-bot',
          'headers': <String, String>{},
        }),
      );
      expect(answer, contains('refused'));
    }
    expect(driver.sent, isEmpty);
  });

  test('a driver the check refuses never sees the request', () async {
    final service = await WebRequestDriverService.start(driver, me, socket);
    addTearDown(service.close);
    final out = await WebRequestDriverSocket(
      socket,
      checkDriver: (_) async => 'not the release it should be',
    ).carryOutWebRequest(Request(api));
    expect((out as Refused).why, contains('not the release it should be'));
    expect(driver.sent, isEmpty);
  });

  test('a driver the check passes carries out the request', () async {
    final service = await WebRequestDriverService.start(driver, me, socket);
    addTearDown(service.close);
    var checked = 0;
    final out = await WebRequestDriverSocket(
      socket,
      checkDriver: (_) async {
        checked++;
        return null;
      },
    ).carryOutWebRequest(Request(api));
    expect(out, isA<Ran<WebResponse>>());
    expect(checked, 1);
    expect(driver.sent, hasLength(1));
  });

  test('says so when no service is listening', () async {
    expect(
      await WebRequestDriverSocket(socket).carryOutWebRequest(Request(api)),
      isA<Refused>(),
    );
  });
}
