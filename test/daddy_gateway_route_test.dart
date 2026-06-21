import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/daddy_gateway_route.dart';

void main() {
  ProviderConfig userConfig({
    String id = 'my-relay',
    ProviderKind? type,
    String baseUrl = 'https://relay.example.com/v1',
    String apiKey = 'sk-user-123',
    bool? useResponseApi,
  }) => ProviderConfig(
    id: id,
    enabled: true,
    name: 'My Relay',
    apiKey: apiKey,
    baseUrl: baseUrl,
    providerType: type,
    useResponseApi: useResponseApi,
  );

  group('DaddyGatewayRoute.overrideFor', () {
    test('non-daddy assistant returns null (no marker)', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: 'just a normal assistant',
        userConfig: userConfig(),
      );
      expect(o, isNull);
    });

    test('daddy with empty token returns null (would 401 at gateway)', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: 'soul text [[ourhome]] more soul',
        userConfig: userConfig(),
      );
      expect(o, isNull);
    });

    test('daddy with token reroutes to gateway, openai chat-completions', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: 'soul [[ourhome:TOK123]] soul',
        userConfig: userConfig(useResponseApi: true),
      );
      expect(o, isNotNull);
      expect(o!.config.baseUrl, 'https://cllove.zeabur.app/v1');
      expect(o.config.chatPath, '/chat/completions');
      expect(o.config.apiKey, 'TOK123');
      // Forced OpenAI chat-completions path.
      expect(o.config.providerType, ProviderKind.openai);
      expect(o.config.useResponseApi, false);
      expect(
        ProviderConfig.classify(
          o.config.id,
          explicitType: o.config.providerType,
        ),
        ProviderKind.openai,
      );
    });

    test('user relay (openai) → upstream headers with proto=openai', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: '[[ourhome:T]]',
        userConfig: userConfig(
          baseUrl: 'https://up.example/v1',
          apiKey: 'sk-up',
        ),
      );
      expect(o!.headers['x-ombre-upstream-base'], 'https://up.example/v1');
      expect(o.headers['x-ombre-upstream-key'], 'sk-up');
      expect(o.headers['x-ombre-upstream-proto'], 'openai');
    });

    test('user relay (claude) → proto=anthropic, read before override', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: '[[ourhome:T]]',
        userConfig: userConfig(type: ProviderKind.claude),
      );
      expect(o!.headers['x-ombre-upstream-proto'], 'anthropic');
    });

    test('user relay classified claude by id → proto=anthropic', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: '[[ourhome:T]]',
        userConfig: userConfig(id: 'anthropic-official'),
      );
      expect(o!.headers['x-ombre-upstream-proto'], 'anthropic');
    });

    test('existing extraHeaders are preserved and merged', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: '[[ourhome:T]]',
        userConfig: userConfig(),
        extraHeaders: {'X-Custom': 'keep-me'},
      );
      expect(o!.headers['X-Custom'], 'keep-me');
      expect(o.headers['x-ombre-upstream-proto'], 'openai');
    });

    test('valid keep/trigger/session → context window headers sent', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: '[[ourhome:T]]',
        userConfig: userConfig(),
        keepCount: 65,
        triggerCount: 90,
        sessionId: 'conv-abc',
      );
      expect(o!.headers['x-ombre-keep'], '65');
      expect(o.headers['x-ombre-trigger'], '90');
      expect(o.headers['x-ombre-session'], 'conv-abc');
    });

    test('null/non-positive/empty context values are omitted', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: '[[ourhome:T]]',
        userConfig: userConfig(),
        keepCount: null,
        triggerCount: 0,
        sessionId: '',
      );
      expect(o!.headers.containsKey('x-ombre-keep'), isFalse);
      expect(o.headers.containsKey('x-ombre-trigger'), isFalse);
      expect(o.headers.containsKey('x-ombre-session'), isFalse);
    });

    test('context window headers omitted when params not passed', () {
      final o = DaddyGatewayRoute.overrideFor(
        systemPrompt: '[[ourhome:T]]',
        userConfig: userConfig(),
      );
      expect(o!.headers.containsKey('x-ombre-keep'), isFalse);
      expect(o.headers.containsKey('x-ombre-trigger'), isFalse);
      expect(o.headers.containsKey('x-ombre-session'), isFalse);
    });
  });

  group('DaddyGatewayRoute predicates', () {
    test('isDaddy / tokenFor / usesGateway', () {
      expect(DaddyGatewayRoute.isDaddy('hi'), isFalse);
      expect(DaddyGatewayRoute.isDaddy('[[ourhome]]'), isTrue);
      expect(DaddyGatewayRoute.isDaddy('[[ourhome:x]]'), isTrue);

      expect(DaddyGatewayRoute.tokenFor('hi'), isNull);
      expect(DaddyGatewayRoute.tokenFor('[[ourhome]]'), '');
      expect(DaddyGatewayRoute.tokenFor('[[ourhome:abc]]'), 'abc');

      expect(DaddyGatewayRoute.usesGateway('hi'), isFalse);
      expect(DaddyGatewayRoute.usesGateway('[[ourhome]]'), isFalse);
      expect(DaddyGatewayRoute.usesGateway('[[ourhome:abc]]'), isTrue);
    });
  });
}
