import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/cc/cc_bridge_client.dart'
    show CcBridgeException, CcAuthException;
import 'package:Kelivo/core/services/cc/group_chat_client.dart';
import 'package:Kelivo/core/services/cc/group_chat_models.dart';

void main() {
  group('GroupMember.fromJson', () {
    test('happy path parses all fields', () {
      final m = GroupMember.fromJson({
        'id': 'shu',
        'display_name': 'Codex',
        'kind': 'agent',
        'avatar': 'C',
        'color': 'green',
        'model': 'Codex GPT-5.5',
        'can_reply': true,
      });
      expect(m.id, 'shu');
      expect(m.displayName, 'Codex');
      expect(m.isAgent, isTrue);
      expect(m.avatar, 'C');
      expect(m.color, 'green');
      expect(m.model, 'Codex GPT-5.5');
      expect(m.canReply, isTrue);
    });

    test('boundary: falls back display_name -> name -> id, empty model null',
        () {
      final m = GroupMember.fromJson({'id': 'x', 'name': 'X', 'model': ''});
      expect(m.displayName, 'X');
      expect(m.model, isNull);
      expect(m.canReply, isFalse);
      final m2 = GroupMember.fromJson({'id': 'y'});
      expect(m2.displayName, 'y');
    });

    test('listFromJson tolerates garbage and drops empty ids', () {
      expect(GroupMember.listFromJson(null), isEmpty);
      expect(GroupMember.listFromJson('nope'), isEmpty);
      final list = GroupMember.listFromJson([
        {'id': 'a', 'kind': 'human'},
        'garbage',
        {'display_name': 'no id'},
        {'id': 'b'},
      ]);
      expect(list.map((m) => m.id), ['a', 'b']);
    });
  });

  group('GroupAgentState', () {
    test('mapFromStatus parses the agents snapshot', () {
      final states = GroupAgentState.mapFromStatus({
        'agents': {
          'shu': {
            'state': 'online',
            'is_typing': true,
            'status_text': 'reading spec',
          },
          'opia': {'state': 'offline'},
        },
      });
      expect(states['shu']?.online, isTrue);
      expect(states['shu']?.isTyping, isTrue);
      expect(states['shu']?.statusText, 'reading spec');
      expect(states['opia']?.online, isFalse);
    });

    test('boundary: tolerates missing/non-map input', () {
      expect(GroupAgentState.mapFromStatus(null), isEmpty);
      expect(GroupAgentState.mapFromStatus('x'), isEmpty);
      expect(GroupAgentState.mapFromStatus({'agents': 'x'}), isEmpty);
    });
  });

  group('GroupRecord.fromJson', () {
    test('happy path parses all fields', () {
      final r = GroupRecord.fromJson({
        'id': 'grp_1_ab',
        'ts': '2026-07-06T10:00:00.000+08:00',
        'sender_id': 'shu',
        'sender_model': 'Codex GPT-5.5',
        'text': '@amian review done, NEEDS_REVISION',
        'mentions': ['amian'],
        'message_type': 'ship',
        'task_id': 't1',
        'parent_task_id': 't0',
        'owner': 'shu',
        'parent_msg_id': 'grp_0_zz',
        'reply_to': 'grp_0_zz',
        'source': 'codex-hook',
        'attachment_url': '/attachments/x.png',
        'attachment_filename': 'x.png',
        'attachment_type': 'image',
      });
      expect(r.id, 'grp_1_ab');
      expect(r.senderId, 'shu');
      expect(r.mentions, ['amian']);
      expect(r.messageType, 'ship');
      expect(r.isChat, isFalse);
      expect(r.taskId, 't1');
      expect(r.hasAttachment, isTrue);
    });

    test('boundary: missing fields default (chat type, empty mentions)', () {
      final r = GroupRecord.fromJson({'id': 'grp_2', 'ts': 'x'});
      expect(r.text, '');
      expect(r.senderId, '');
      expect(r.mentions, isEmpty);
      expect(r.messageType, 'chat');
      expect(r.isChat, isTrue);
      expect(r.hasAttachment, isFalse);
    });

    test('listFromJson tolerates garbage and drops records without id', () {
      final list = GroupRecord.listFromJson([
        {'id': 'a', 'ts': '1'},
        'garbage',
        {'ts': 'no-id'},
        {'id': 'b', 'ts': '2'},
      ]);
      expect(list.map((r) => r.id), ['a', 'b']);
    });
  });

  group('GroupPollResult / GroupRosterResult', () {
    test('poll parses records, cursor and status', () {
      final p = GroupPollResult.fromJson({
        'ok': true,
        'records': [
          {'id': 'a', 'ts': '1', 'sender_id': 'shu', 'text': 'hi'},
        ],
        'last_ts': '1',
        'status': {
          'agents': {
            'shu': {'state': 'online'},
          },
        },
      });
      expect(p.records.single.text, 'hi');
      expect(p.lastTs, '1');
      expect(p.agentStates['shu']?.online, isTrue);
    });

    test('humanSenderId picks the human member, falls back to amian', () {
      final roster = GroupRosterResult.fromJson({
        'roster': [
          {'id': 'opia', 'kind': 'agent'},
          {'id': 'kitten', 'kind': 'human'},
        ],
      });
      expect(roster.humanSenderId, 'kitten');
      final empty = GroupRosterResult.fromJson(const {});
      expect(empty.members, isEmpty);
      expect(empty.humanSenderId, 'amian');
    });
  });

  group('GroupChatClient against a local server', () {
    late HttpServer server;
    late GroupChatClient client;
    String? seenAuth;
    Uri? seenUri;
    Map<String, dynamic>? seenBody;
    List<int>? seenRawBody;
    int rosterStatus = 200;
    int sendStatus = 200;

    setUp(() async {
      seenAuth = null;
      seenUri = null;
      seenBody = null;
      seenRawBody = null;
      rosterStatus = 200;
      sendStatus = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seenAuth = req.headers.value('X-Auth-Token');
        seenUri = req.uri;
        req.response.headers.contentType = ContentType.json;
        switch (req.uri.path) {
          case '/group/roster':
            req.response.statusCode = rosterStatus;
            req.response.write(jsonEncode({
              'ok': true,
              'roster': [
                {'id': 'amian', 'kind': 'human', 'display_name': 'User'},
                {
                  'id': 'shu',
                  'kind': 'agent',
                  'display_name': 'Codex',
                  'can_reply': true,
                },
              ],
              'status': {
                'agents': {
                  'shu': {'state': 'online'},
                },
              },
            }));
            break;
          case '/group/poll':
            req.response.write(jsonEncode({
              'ok': true,
              'records': [
                {'id': 'grp_1', 'ts': '2', 'sender_id': 'shu', 'text': 'ok'},
              ],
              'last_ts': '2',
              'status': {'agents': {}},
            }));
            break;
          case '/group/send':
            final bodyText = await utf8.decoder.bind(req).join();
            seenBody = jsonDecode(bodyText) as Map<String, dynamic>;
            req.response.statusCode = sendStatus;
            if (sendStatus == 429) {
              req.response.write(jsonEncode({
                'ok': false,
                'error': 'duplicate within 3s window',
                'deduped': true,
              }));
            } else {
              req.response.write(jsonEncode({
                'ok': true,
                'record': {
                  'id': 'grp_2',
                  'ts': '3',
                  'sender_id': seenBody?['sender_id'],
                  'text': seenBody?['text'],
                },
                'targets': ['shu'],
              }));
            }
            break;
          case '/group/upload':
            seenRawBody =
                await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
            req.response.write(jsonEncode({
              'ok': true,
              'record': {
                'id': 'grp_3',
                'ts': '4',
                'sender_id': req.uri.queryParameters['sender_id'],
                'text': req.uri.queryParameters['text'] ?? '',
                'attachment_url': '/attachments/up.png',
                'attachment_type': 'image',
              },
            }));
            break;
          default:
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'error': 'not found'}));
        }
        await req.response.close();
      });
      client = GroupChatClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        sharedSecret: 'secret',
      );
    });

    tearDown(() async {
      client.dispose();
      await server.close(force: true);
    });

    test('roster sends the shared secret and parses members + status',
        () async {
      final r = await client.roster();
      expect(seenAuth, 'secret');
      expect(r.members.length, 2);
      expect(r.humanSenderId, 'amian');
      expect(r.agentStates['shu']?.online, isTrue);
    });

    test('roster 404 surfaces the status code (server too old)', () async {
      rosterStatus = 404;
      await expectLater(
        client.roster(),
        throwsA(isA<CcBridgeException>()
            .having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('poll passes since/viewer/limit and parses the page', () async {
      final p = await client.poll(since: '1', viewer: 'amian', limit: 50);
      expect(seenUri?.queryParameters['since'], '1');
      expect(seenUri?.queryParameters['viewer'], 'amian');
      expect(seenUri?.queryParameters['limit'], '50');
      expect(p.records.single.id, 'grp_1');
      expect(p.lastTs, '2');
    });

    test('send posts sender_id/text and parses record + targets', () async {
      final res = await client.send(
        '@shu review this',
        senderId: 'amian',
        clientMsgId: 'cm1',
      );
      expect(seenBody?['sender_id'], 'amian');
      expect(seenBody?['text'], '@shu review this');
      expect(seenBody?['client_msg_id'], 'cm1');
      expect(seenBody?['source'], 'ios-app');
      expect(res.ok, isTrue);
      expect(res.record?.id, 'grp_2');
      expect(res.targets, ['shu']);
    });

    test('failure path: send 429 maps to deduped, not thrown', () async {
      sendStatus = 429;
      final res = await client.send('dup', senderId: 'amian');
      expect(res.ok, isFalse);
      expect(res.deduped, isTrue);
    });

    test('upload sends raw bytes with metadata in the query', () async {
      final res = await client.upload(
        [1, 2, 3],
        filename: 'up.png',
        senderId: 'amian',
        text: 'caption',
      );
      expect(seenRawBody, [1, 2, 3]);
      expect(seenUri?.queryParameters['filename'], 'up.png');
      expect(seenUri?.queryParameters['sender_id'], 'amian');
      expect(seenUri?.queryParameters['text'], 'caption');
      expect(res.ok, isTrue);
      expect(res.record?.hasAttachment, isTrue);
    });

    test('failure path: 401 throws CcAuthException', () async {
      final authServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      authServer.listen((req) async {
        req.response.statusCode = 401;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'unauthorized'}));
        await req.response.close();
      });
      final c = GroupChatClient(
        baseUrl: 'http://127.0.0.1:${authServer.port}',
        sharedSecret: 'wrong',
      );
      try {
        await expectLater(c.roster(), throwsA(isA<CcAuthException>()));
      } finally {
        c.dispose();
        await authServer.close(force: true);
      }
    });
  });
}
