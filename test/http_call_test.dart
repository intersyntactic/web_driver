import 'dart:io';

import 'package:is_web_request_driver/is_web_request_driver.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer site;
  late HttpServer elsewhere;
  late List<String> reachedElsewhere;

  setUp(() async {
    reachedElsewhere = [];
    elsewhere = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    elsewhere.listen((r) async {
      await r.drain<void>();
      reachedElsewhere.add('${r.method} ${r.uri}');
      await r.response.close();
    });
    site = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    site.listen((r) async {
      await r.drain<void>();
      final status = int.tryParse(r.uri.queryParameters['status'] ?? '');
      if (status != null) {
        r.response
          ..statusCode = status
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${elsewhere.port}/file?sig=temporary',
          );
      } else {
        r.response.write('answered');
      }
      await r.response.close();
    });
  });

  tearDown(() async {
    await site.close(force: true);
    await elsewhere.close(force: true);
  });

  Uri url(String query) => Uri.parse('http://127.0.0.1:${site.port}/$query');

  for (final (method, status) in [
    ('GET', 301),
    ('GET', 302),
    ('GET', 303),
    ('GET', 307),
    ('GET', 308),
    ('HEAD', 302),
    ('POST', 303),
  ]) {
    test('answers a $method redirect $status without following it', () async {
      final r = await httpCall(method, url('?status=$status'), {
        'authorization': 'Bearer token',
        'x-tool': 'header',
      }, '');
      expect(r.status, status);
      expect(reachedElsewhere, isEmpty);
    });
  }

  test('carries out a request that is not redirected', () async {
    final r = await httpCall('POST', url(''), {}, 'body');
    expect(r, (status: 200, body: 'answered'));
  });
}
