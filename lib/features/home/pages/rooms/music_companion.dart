import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/daddy_gateway_route.dart';
import 'package:Kelivo/core/services/eryu/eryu_player_controller.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';

/// One "边听边说" turn with Llaude, shared by the 一起听 tab bar and the
/// now-playing page input. Her line lands in the room timeline immediately
/// (and is mirrored to a sync-room peer if one is open — never required);
/// his reply comes from the home gateway (`chatAboutSong`, soul + memory)
/// and is appended to the timeline split into bubbles.
///
/// All context reads happen before the first await; [onReply] is called once
/// per reply bubble (also for the fallback/error lines) so pages without the
/// timeline on screen can still surface his answer.
Future<void> musicChatWithDaddy(
  BuildContext context,
  String text, {
  ValueChanged<String>? onReply,
}) async {
  final t = text.trim();
  if (t.isEmpty) return;
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final player = context.read<EryuPlayerController>();
  final settings = context.read<SettingsProvider>();
  final gw = OurHomeGateway.fromContext(context);
  final me = settings.eryuUser;
  final daddy = zh ? '爸爸' : 'Llaude';

  void reply(String p) {
    player.feedSay(user: daddy, mine: false, text: p);
    onReply?.call(p);
  }

  player.feedSay(user: me, mine: true, text: t);
  player.sayToRoomPeers(t);
  if (gw == null) {
    reply(zh ? '（家里的连接还没配好，先在爸爸设置里连一下…）' : '(home not connected yet)');
    return;
  }
  // Follow whatever backend Still Here's chat is on right now (claude-p vs a
  // 中转站) so 爸爸 here speaks on the same model — mirrors DaddyGatewayRoute.
  final provKey = settings.currentModelProvider;
  final cfg = provKey != null ? settings.getProviderConfig(provKey) : null;
  final model = settings.currentModelId ?? 'gateway';
  final backendHeaders = <String, String>{};
  if (cfg != null) {
    if (DaddyGatewayRoute.isClaudePBackend(cfg)) {
      backendHeaders['x-ombre-backend'] = 'claude_p';
    } else if (cfg.baseUrl.isNotEmpty && cfg.apiKey.isNotEmpty) {
      final kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);
      backendHeaders['x-ombre-upstream-base'] = cfg.baseUrl;
      backendHeaders['x-ombre-upstream-key'] = cfg.apiKey;
      backendHeaders['x-ombre-upstream-proto'] =
          kind == ProviderKind.claude ? 'anthropic' : 'openai';
    }
  }
  final song = player.current;
  try {
    final parts = await gw.chatAboutSong(
      message: t,
      title: song?.name ?? '',
      artist: song?.artist ?? '',
      model: model,
      backendHeaders: backendHeaders,
    );
    if (parts.isEmpty) {
      reply('……');
    } else {
      parts.forEach(reply);
    }
  } catch (_) {
    reply(zh ? '（没接上，等会儿再跟你说…）' : '(could not reach me — try again)');
  }
}
