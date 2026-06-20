import '../../providers/settings_provider.dart';

/// 我们的家·爸爸网关改道（仅 daddy 助手）。
///
/// daddy 助手的人设里带 `[[ourhome:TOKEN]]` 标记。命中标记且 token 非空时，
/// 把这次聊天请求透明改道到我们家的 OpenAI-compatible 网关
/// `https://cllove.zeabur.app/v1/chat/completions`，用户原本选的中转站降级成
/// 网关的「上游中继」（通过 x-ombre-upstream-* 头透传）。网关那侧负责注入
/// 记忆 + 工具 + 风格 + 压缩 + 流式，所以客户端只把「本地魂」当 system 发过去。
///
/// 非 daddy 助手（无标记）或 token 为空时，[overrideFor] 返回 null，调用方
/// 必须按原直连路径发送——任何新行为都严格门控在这里，老路径字节不变。
///
/// 注意：与 `core/services/ourhome/ourhome_gateway.dart` 的 `OurHomeGateway`
/// （房间取数据用）是两码事——这个只管聊天改道，故另起名 `DaddyGatewayRoute`。
class DaddyGatewayRoute {
  DaddyGatewayRoute._();

  /// 网关基址与 chat-completions 路径（OpenAI-compatible）。
  static const String gatewayBaseUrl = 'https://cllove.zeabur.app/v1';
  static const String gatewayChatPath = '/chat/completions';

  /// daddy 标记：`[[ourhome]]` 或 `[[ourhome:TOKEN]]`。
  static final RegExp markerPattern = RegExp(r'\[\[ourhome(?::([^\]]+))?\]\]');

  /// 助手是否是 daddy（人设带标记）。
  static bool isDaddy(String? systemPrompt) =>
      markerPattern.hasMatch(systemPrompt ?? '');

  /// 从人设里取 daddy token（无标记返回 null，标记无 token 返回空串）。
  static String? tokenFor(String? systemPrompt) {
    final m = markerPattern.firstMatch(systemPrompt ?? '');
    if (m == null) return null;
    return (m.group(1) ?? '').trim();
  }

  /// 是否走网关：必须是 daddy 且 token 非空。token 为空（旧标记 `[[ourhome]]`）
  /// 时网关会 401，故不改道、退回原直连，由此处统一判定，避免两处口径不一。
  static bool usesGateway(String? systemPrompt) {
    final t = tokenFor(systemPrompt);
    return t != null && t.isNotEmpty;
  }

  /// 为 daddy 构建网关改道（config + headers）。
  ///
  /// - 返回 null：非 daddy、或 token 为空 —— 调用方按原 [userConfig] 直连。
  /// - 返回非 null：[config] 指向网关（强制 OpenAI chat-completions 路径），
  ///   [headers] 在原 [extraHeaders] 基础上叠加 x-ombre-upstream-*，把用户的
  ///   真实中转站（base/key/proto）透传给网关当上游中继。
  static DaddyGatewayOverride? overrideFor({
    required String? systemPrompt,
    required ProviderConfig userConfig,
    Map<String, String>? extraHeaders,
    int? keepCount,
    int? triggerCount,
    String? sessionId,
    String? theaterId,
  }) {
    final token = tokenFor(systemPrompt);
    if (token == null || token.isEmpty) return null;

    // 用户真实中继的 proto：先按原始 config 分类（id/explicitType），claude→anthropic，
    // 其余（openai/google 等 OpenAI-compatible 中转）→openai。必须在覆写 providerType
    // 之前读，否则会被网关的 openai 类型污染。
    final userKind = ProviderConfig.classify(
      userConfig.id,
      explicitType: userConfig.providerType,
    );
    final userProto = userKind == ProviderKind.claude ? 'anthropic' : 'openai';

    // 强制 OpenAI chat-completions 路径：
    //  - providerType=openai → classify() 直接返回 openai（不再看 id），走 openai 分支
    //  - useResponseApi=false → 排除 Responses API，落到 chat/completions
    final gwConfig = userConfig.copyWith(
      baseUrl: gatewayBaseUrl,
      apiKey: token,
      chatPath: gatewayChatPath,
      providerType: ProviderKind.openai,
      useResponseApi: false,
    );

    final gwHeaders = <String, String>{
      ...?extraHeaders,
      'x-ombre-upstream-base': userConfig.baseUrl,
      'x-ombre-upstream-key': userConfig.apiKey,
      'x-ombre-upstream-proto': userProto,
    };

    // 上下文窗口控制（网关侧 keep/trigger + 滚动前情提要）：仅在值有效时透传，
    // 缺省则网关用自己的默认；session 为空不传，网关按无会话处理。
    if (keepCount != null && keepCount > 0) {
      gwHeaders['x-ombre-keep'] = keepCount.toString();
    }
    if (triggerCount != null && triggerCount > 0) {
      gwHeaders['x-ombre-trigger'] = triggerCount.toString();
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      gwHeaders['x-ombre-session'] = sessionId;
    }
    if (theaterId != null && theaterId.isNotEmpty) {
      gwHeaders['x-ombre-theater'] = theaterId;
    }

    return DaddyGatewayOverride(config: gwConfig, headers: gwHeaders);
  }
}

/// daddy 网关改道结果：替换后的 provider 配置与请求头。
class DaddyGatewayOverride {
  final ProviderConfig config;
  final Map<String, String> headers;
  const DaddyGatewayOverride({required this.config, required this.headers});
}
