import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:Kelivo/core/services/network/dio_http_client.dart';

void main() {
  test('response-header failure retries once with a fresh transport', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var attempts = 0;
    server.listen((request) async {
      attempts += 1;
      await request.drain();
      if (attempts == 1) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        await socket.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true}));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final client = DioHttpClient(retryConnectionBeforeHeaders: (_) => true);
    addTearDown(client.close);
    final request = http.Request(
      'POST',
      Uri.parse('http://127.0.0.1:${server.port}/chat'),
    )..body = jsonEncode({'message': 'hello'});

    final response = await client.send(request);
    final body = await response.stream.bytesToString();

    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(body), {'ok': true});
    expect(attempts, 2);
  });

  test(
    'silent response-header hang fails once without duplicate send',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final releaseResponse = Completer<void>();
      var attempts = 0;
      server.listen((request) async {
        attempts += 1;
        await request.drain();
        await releaseResponse.future;
        try {
          await request.response.close();
        } catch (_) {}
      });
      addTearDown(() async {
        if (!releaseResponse.isCompleted) releaseResponse.complete();
        await server.close(force: true);
      });

      final client = DioHttpClient(
        retryConnectionBeforeHeaders: (_) => false,
        responseHeaderTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(client.close);
      final request = http.Request(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}/chat'),
      )..body = jsonEncode({'message': 'hello'});
      final stopwatch = Stopwatch()..start();

      await expectLater(
        client.send(request),
        throwsA(
          isA<http.ClientException>().having(
            (error) => error.message,
            'message',
            contains('No response headers within'),
          ),
        ),
      );
      stopwatch.stop();

      expect(attempts, 1);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );
}
