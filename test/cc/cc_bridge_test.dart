import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/cc/cc_bridge_client.dart';
import 'package:Kelivo/core/services/cc/cc_bridge_models.dart';

void main() {
  group('CcChatRecord.fromJson', () {
    test('happy path parses all fields', () {
      final r = CcChatRecord.fromJson({
        'ts': '2026-06-21T10:00:00.000+08:00',
        'role': 'assistant',
        'text': '想你了',
        'source': 'cc',
        'turn_id': 't1',
        'quoted_ts': '2026-06-21T09:59:00.000+08:00',
        'quoted_text': 'q',
        'attachment_url': '/attachments/a.png',
        'attachment_type': 'image',
        'attachment_filename': 'a.png',
        'location': {'lat': 31.2, 'lon': 121.4, 'label': '家'},
        'metadata': {'k': 'v'},
      });
      expect(r.ts, '2026-06-21T10:00:00.000+08:00');
      expect(r.isAssistant, isTrue);
      expect(r.text, '想你了');
      expect(r.turnId, 't1');
      expect(r.hasAttachment, isTrue);
      expect(r.location?['label'], '家');
      expect(r.metadata?['k'], 'v');
    });

    test('boundary: missing optional fields become null/empty', () {
      final r = CcChatRecord.fromJson({'ts': 'x', 'role': 'user'});
      expect(r.text, '');
      expect(r.isUser, isTrue);
      expect(r.turnId, isNull);
      expect(r.source, isNull);
      expect(r.location, isNull);
      expect(r.hasAttachment, isFalse);
    });

    test('listFromJson tolerates non-list and non-map entries', () {
      expect(CcChatRecord.listFromJson(null), isEmpty);
      expect(CcChatRecord.listFromJson('nope'), isEmpty);
      final list = CcChatRecord.listFromJson([
        {'ts': '1', 'role': 'user', 'text': 'a'},
        'garbage',
        {'ts': '2', 'role': 'assistant', 'text': 'b'},
      ]);
      expect(list.length, 2);
      expect(list[1].text, 'b');
    });
  });

  group('CcPollResult.fromJson', () {
    test('happy path with unchanged settings', () {
      final p = CcPollResult.fromJson({
        'now': '2026-06-21T10:00:00.123+08:00',
        'chat': {
          'new_records': [
            {'ts': '1', 'role': 'assistant', 'text': 'hi'},
          ],
          'last_ts': '1',
          'count': 1,
        },
        'status': {'status': 'typing', 'is_typing': true},
        'settings': {'unchanged': true, 'etag': 'abc'},
      });
      expect(p.count, 1);
      expect(p.lastTs, '1');
      expect(p.newRecords.single.text, 'hi');
      expect(p.status.status, CcAgentStatus.typing);
      expect(p.status.isTyping, isTrue);
      expect(p.settingsChanged, isFalse);
      expect(p.settingsEtag, 'abc');
    });

    test('settings changed carries values', () {
      final p = CcPollResult.fromJson({
        'chat': {'new_records': [], 'last_ts': null, 'count': 0},
        'status': {'status': 'sleeping'},
        'settings': {
          'unchanged': false,
          'etag': 'def',
          'values': {'tts_enabled': true},
        },
      });
      expect(p.newRecords, isEmpty);
      expect(p.status.status, CcAgentStatus.sleeping);
      expect(p.settingsChanged, isTrue);
      expect(p.settingsValues?['tts_enabled'], true);
    });

    test('boundary: empty json yields safe defaults', () {
      final p = CcPollResult.fromJson({});
      expect(p.count, 0);
      expect(p.newRecords, isEmpty);
      expect(p.status.status, CcAgentStatus.unknown);
      expect(p.settingsChanged, isFalse);
    });
  });

  group('CcBridgeConfig', () {
    test('toJson/fromJson round-trips', () {
      const cfg = CcBridgeConfig(
        endpoints: ['http://100.1.1.1:8795', 'http://10.0.0.2:8795'],
        sharedSecret: 's3cr3t',
        session: 'cc',
        pollIntervalMs: 3000,
        remoteControlEnabled: true,
        enabled: true,
      );
      final back = CcBridgeConfig.fromJson(
        jsonDecode(jsonEncode(cfg.toJson())) as Map<String, dynamic>,
      );
      expect(back.endpoints, cfg.endpoints);
      expect(back.sharedSecret, 's3cr3t');
      expect(back.remoteControlEnabled, isTrue);
      expect(back.pollIntervalMs, 3000);
      expect(back.isConfigured, isTrue);
    });

    test('fromJson applies defaults for missing/blank fields', () {
      final c = CcBridgeConfig.fromJson({});
      expect(c.endpoints, isEmpty);
      expect(c.session, 'cc');
      expect(c.pollIntervalMs, 2500);
      expect(c.enabled, isFalse);
      expect(c.isConfigured, isFalse);
    });
  });

  group('CcBridgeClient.normalizeBaseUrl', () {
    test('adds http scheme when missing', () {
      expect(CcBridgeClient.normalizeBaseUrl('100.1.1.1:8795'),
          'http://100.1.1.1:8795');
    });
    test('keeps existing scheme and strips trailing slash', () {
      expect(CcBridgeClient.normalizeBaseUrl('https://x.y:8795/'),
          'https://x.y:8795');
      expect(CcBridgeClient.normalizeBaseUrl('http://a:1///'), 'http://a:1');
    });
    test('empty stays empty', () {
      expect(CcBridgeClient.normalizeBaseUrl('   '), '');
    });
  });

  group('CcTmuxCapture.fromJson', () {
    test('reads content key', () {
      final c = CcTmuxCapture.fromJson({
        'content': r'$ claude',
        'session': 'cc',
        'lines': 120,
      });
      expect(c.content, r'$ claude');
      expect(c.session, 'cc');
      expect(c.lines, 120);
    });

    test('falls back across text/output/pane keys', () {
      expect(CcTmuxCapture.fromJson({'text': 'a'}).content, 'a');
      expect(CcTmuxCapture.fromJson({'output': 'b'}).content, 'b');
      expect(CcTmuxCapture.fromJson({'pane': 'c'}).content, 'c');
    });

    test('boundary: empty json yields empty content', () {
      final c = CcTmuxCapture.fromJson({});
      expect(c.content, '');
      expect(c.session, isNull);
      expect(c.lines, isNull);
    });
  });

  group('CcChainSessions.fromJson', () {
    test('happy path parses sessions and active sid', () {
      final s = CcChainSessions.fromJson({
        'sessions': [
          {'sid': 'cc', 'active': true},
          {'sid': 'cc2', 'active': false},
        ],
        'active_sid': 'cc',
      });
      expect(s.sessions.length, 2);
      expect(s.sessions.first.sid, 'cc');
      expect(s.sessions.first.active, isTrue);
      expect(s.activeSid, 'cc');
    });

    test('boundary: missing/garbage sessions yields empty', () {
      expect(CcChainSessions.fromJson({}).sessions, isEmpty);
      expect(
        CcChainSessions.fromJson({'sessions': 'nope'}).sessions,
        isEmpty,
      );
    });
  });

  group('CcBridgeClient RC endpoints against a local server', () {
    late HttpServer server;
    late CcBridgeClient client;
    String? seenPath;
    Map<String, dynamic>? seenBody;

    setUp(() async {
      seenPath = null;
      seenBody = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seenPath = req.uri.path;
        req.response.headers.contentType = ContentType.json;
        switch (req.uri.path) {
          case '/tmux/capture':
            req.response.write(jsonEncode({
              'content': 'pane for ${req.uri.queryParameters['session']}',
              'session': req.uri.queryParameters['session'],
              'lines': int.tryParse(req.uri.queryParameters['lines'] ?? ''),
            }));
            break;
          case '/chain/sessions':
            req.response.write(jsonEncode({
              'sessions': [
                {'sid': 'cc', 'active': true},
              ],
              'active_sid': 'cc',
            }));
            break;
          default:
            final bodyText = await utf8.decoder.bind(req).join();
            if (bodyText.isNotEmpty) {
              seenBody = jsonDecode(bodyText) as Map<String, dynamic>;
            }
            req.response.write(jsonEncode({'ok': true}));
        }
        await req.response.close();
      });
      client = CcBridgeClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        sharedSecret: 'secret',
      );
    });

    tearDown(() async {
      client.dispose();
      await server.close(force: true);
    });

    test('tmuxCapture passes session/lines and parses content', () async {
      final cap = await client.tmuxCapture(session: 'cc', lines: 80);
      expect(cap.content, 'pane for cc');
      expect(cap.session, 'cc');
      expect(seenPath, '/tmux/capture');
    });

    test('tmuxSend sends literal keys with enter flag', () async {
      await client.tmuxSend(session: 'cc', keys: '/compact', enter: true);
      expect(seenPath, '/tmux/send');
      expect(seenBody?['session'], 'cc');
      expect(seenBody?['keys'], '/compact');
      expect(seenBody?['enter'], true);
    });

    test('tmuxSend sends a whitelisted special key', () async {
      await client.tmuxSend(session: 'cc', key: 'C-c');
      expect(seenBody?['key'], 'C-c');
    });

    test('tmuxSend rejects a non-whitelisted key', () async {
      await expectLater(
        client.tmuxSend(session: 'cc', key: 'rm -rf'),
        throwsA(isA<CcBridgeException>()),
      );
    });

    test('chainSessions parses the list and active sid', () async {
      final s = await client.chainSessions();
      expect(s.sessions.single.sid, 'cc');
      expect(s.activeSid, 'cc');
    });

    test('chainSwitch posts the sid', () async {
      await client.chainSwitch('cc2');
      expect(seenPath, '/chain/switch');
      expect(seenBody?['sid'], 'cc2');
    });

    test('chainClear posts the session', () async {
      await client.chainClear('cc');
      expect(seenPath, '/chain/clear');
      expect(seenBody?['session'], 'cc');
    });
  });

  group('CcBridgeClient against a local server', () {
    late HttpServer server;
    late CcBridgeClient client;
    String? seenAuth;
    Map<String, dynamic>? seenSendBody;

    setUp(() async {
      seenAuth = null;
      seenSendBody = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seenAuth = req.headers.value('X-Auth-Token');
        final path = req.uri.path;

        // Auth gate: 401 when secret required but absent/wrong.
        if (path != '/health' && seenAuth != 'secret') {
          req.response.statusCode = 401;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'error': 'unauthorized'}));
          await req.response.close();
          return;
        }

        req.response.headers.contentType = ContentType.json;
        switch (path) {
          case '/chat/send':
            final bodyText = await utf8.decoder.bind(req).join();
            seenSendBody = jsonDecode(bodyText) as Map<String, dynamic>;
            if (seenSendBody!['text'] == 'unreachable') {
              req.response.statusCode = 502;
              req.response.write(jsonEncode({
                'ok': false,
                'error': "inject to tmux session 'cc' failed",
                'record': {'ts': 't', 'role': 'user', 'text': 'unreachable'},
              }));
            } else {
              req.response.write(jsonEncode({
                'ok': true,
                'record': {
                  'ts': 't1',
                  'role': 'user',
                  'text': seenSendBody!['text'],
                },
              }));
            }
            break;
          case '/chat/poll':
            req.response.write(jsonEncode({
              'now': 'now',
              'chat': {
                'new_records': [
                  {'ts': '2', 'role': 'assistant', 'text': 'reply'},
                ],
                'last_ts': '2',
                'count': 1,
              },
              'status': {'status': 'online', 'is_typing': false},
              'settings': {'unchanged': true, 'etag': 'e'},
            }));
            break;
          default:
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'error': 'not found'}));
        }
        await req.response.close();
      });
      client = CcBridgeClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        sharedSecret: 'secret',
      );
    });

    tearDown(() async {
      client.dispose();
      await server.close(force: true);
    });

    test('send happy path returns ok with record and sends auth header',
        () async {
      final res = await client.send('hello');
      expect(res.ok, isTrue);
      expect(res.agentUnreachable, isFalse);
      expect(res.record?.text, 'hello');
      expect(seenAuth, 'secret');
      expect(seenSendBody?['text'], 'hello');
    });

    test('send maps HTTP 502 to agentUnreachable, keeps record', () async {
      final res = await client.send('unreachable');
      expect(res.ok, isFalse);
      expect(res.agentUnreachable, isTrue);
      expect(res.record?.text, 'unreachable');
      expect(res.error, contains('failed'));
    });

    test('poll returns records and advances cursor', () async {
      final res = await client.poll(since: '1');
      expect(res.count, 1);
      expect(res.lastTs, '2');
      expect(res.newRecords.single.text, 'reply');
      expect(res.status.status, CcAgentStatus.online);
    });

    test('wrong secret raises CcAuthException', () async {
      final bad = CcBridgeClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        sharedSecret: 'wrong',
      );
      addTearDown(bad.dispose);
      expect(
        () => bad.poll(),
        throwsA(isA<CcAuthException>()),
      );
    });
  });
}
