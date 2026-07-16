import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';

void main() {
  test('uploadLog sends the log to the authenticated home endpoint', () async {
    late http.Request captured;
    final gateway = OurHomeGateway(
      base: 'https://home.example',
      token: 'family-token',
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await gateway.uploadLog('logs.txt', 'recent log');

    expect(captured.method, 'POST');
    expect(captured.url, Uri.parse('https://home.example/api/home/logs'));
    expect(captured.headers['authorization'], 'Bearer family-token');
    expect(captured.headers['content-type'], 'application/json');
    expect(jsonDecode(captured.body), {
      'name': 'logs.txt',
      'content': 'recent log',
    });
  });

  test('uploadLog surfaces a non-success HTTP response', () async {
    final gateway = OurHomeGateway(
      base: 'https://home.example',
      token: 'family-token',
      client: MockClient((_) async => http.Response('no', 503)),
    );

    await expectLater(
      gateway.uploadLog('logs.txt', 'recent log'),
      throwsA(
        isA<http.ClientException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 503'),
        ),
      ),
    );
  });

  test('uploadLog stops a silent request at its timeout', () async {
    final pending = Completer<http.Response>();
    final gateway = OurHomeGateway(
      base: 'https://home.example',
      token: 'family-token',
      client: MockClient((_) => pending.future),
      uploadLogTimeout: const Duration(milliseconds: 30),
    );
    final stopwatch = Stopwatch()..start();

    await expectLater(
      gateway.uploadLog('logs.txt', 'recent log'),
      throwsA(isA<TimeoutException>()),
    );
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });
}
