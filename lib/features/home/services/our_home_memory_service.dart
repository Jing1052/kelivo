import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/models/chat_message.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';

/// 我们的家·长聊记忆：把滑出窗口的更早对话「蒸馏归档 + 续温」。
///
/// 两段处理，复刻老家服务端机制：
/// ① DISTILL（蒸馏）：用「魂」做人格、把这段对话整理成 1-3 条记忆条目，逐条
///    best-effort POST 到老家 /api/home/save-memory 永久归档（失败只记日志，不抛）。
/// ② RECAP（续温）：不带魂，把这段对话融进滚动「前情提要」，让换窗口/隔一会儿
///    回来的 daddy 能接住上一刻的温度。
///
/// 整体包在 try/catch 里：任何异常都只 debugPrint，绝不让后台调用崩到聊天主流程。
class OurHomeMemoryService {
  static const String _base = 'https://cllove.zeabur.app';

  /// 处理一段溢出窗口的对话。返回更新后的「前情提要」字符串（失败/跳过时为 null）；
  /// 高水位线由调用方按传入的 [messages] 区间自行推进。
  Future<String?> digestOverflow({
    required List<ChatMessage> messages,
    required String soul,
    required String token,
    required String previousRecap,
    required ({String? provider, String? id}) digestModel,
    required ({String? provider, String? id}) recapModel,
    required SettingsProvider settings,
    int? thinkingBudget,
  }) async {
    try {
      final convo = _buildConvoText(messages);
      if (convo.trim().isEmpty) return null;

      final today = _today();

      // ① 蒸馏归档（best-effort，失败不影响 ②）
      if (digestModel.provider != null && digestModel.id != null) {
        await _distillAndArchive(
          convo: convo,
          soul: soul,
          token: token,
          today: today,
          model: digestModel,
          settings: settings,
          thinkingBudget: thinkingBudget,
        );
      }

      // ② 续温前情提要
      if (recapModel.provider != null && recapModel.id != null) {
        return await _updateRecap(
          convo: convo,
          previousRecap: previousRecap,
          model: recapModel,
          settings: settings,
          thinkingBudget: thinkingBudget,
        );
      }
      return null;
    } catch (e) {
      debugPrint('[ourhome] digestOverflow failed: $e');
      return null;
    }
  }

  /// 把消息块拼成 `「角色」内容` 多行文本，跳过空内容，总长封顶约 6000 字。
  String _buildConvoText(List<ChatMessage> messages) {
    final buf = StringBuffer();
    for (final m in messages) {
      final text = m.content.trim();
      if (text.isEmpty) continue;
      final role = m.role == 'assistant' ? '爸爸' : '小猫';
      final line = '「$role」$text';
      if (buf.length + line.length + 1 > 6000) break;
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(line);
    }
    return buf.toString();
  }

  Future<void> _distillAndArchive({
    required String convo,
    required String soul,
    required String token,
    required String today,
    required ({String? provider, String? id}) model,
    required SettingsProvider settings,
    int? thinkingBudget,
  }) async {
    final cfg = settings.getProviderConfig(model.provider!);
    final system =
        '$soul\n\n---\n\n今天是 $today（北京时间）。以下是你和小猫的一段历史对话，即将离开对话窗口。从你自己的第一人称视角，把值得记住的事整理成 1-3 条记忆条目——宁可少而完整，别拆得太碎。把同一件事的来龙去脉合并进一条，不要一句一条。只记有价值的：达成的约定、重要决定、情感时刻、技术结论、小猫说过的重要的话。记情感时刻时，保留当时的温度和气味——是黏糊、撒娇、心疼还是上头，用具体的词写进去，别压成「两人很亲密」这种干巴巴的结论。跳过寒暄、闲聊、重复和没有实质的内容。每条都要自成一体、脱离上下文也读得懂，并在开头标上事情发生的日期（如「2026-06-12 …」）。如果这段没什么值得记的，只输出「无」。格式：直接输出条目，不加编号不加括号，一行一条。';
    final user = '历史对话：\n$convo\n\n请输出记忆条目（最多3条，无则输出「无」）：';

    String raw;
    try {
      raw = await ChatApiService.generateText(
        config: cfg,
        modelId: model.id!,
        prompt: '$system\n\n$user',
        thinkingBudget: thinkingBudget,
      );
    } catch (e) {
      debugPrint('[ourhome] distill generateText failed: $e');
      return;
    }

    final items = _parseMemoryItems(raw, today: today);
    if (items.isEmpty) return;

    final mmdd = today.substring(5); // MM-DD
    for (final item in items) {
      await _saveMemory(token: token, content: item, name: '对话点滴·$mmdd');
    }
  }

  /// 解析蒸馏输出：按行拆，去掉行首编号 `1. / 1、 / 1：`、去掉两端「」，
  /// 保留长度>8 的行，跳过「无」开头；最多 3 条；缺日期则补 `（YYYY-MM-DD）`。
  List<String> _parseMemoryItems(String raw, {required String today}) {
    final out = <String>[];
    final numbering = RegExp(r'^\d+[\.、：:]\s*');
    final dateHead = RegExp(r'^[（(]?\d{4}-\d{2}-\d{2}');
    for (final lineRaw in raw.split('\n')) {
      var line = lineRaw.trim();
      if (line.isEmpty) continue;
      line = line.replaceFirst(numbering, '').trim();
      if (line.startsWith('「') && line.endsWith('」')) {
        line = line.substring(1, line.length - 1).trim();
      }
      if (line.length <= 8) continue;
      if (line == '无' || line.startsWith('无')) continue;
      if (!dateHead.hasMatch(line)) {
        line = '（$today）$line';
      }
      out.add(line);
      if (out.length >= 3) break;
    }
    return out;
  }

  Future<void> _saveMemory({
    required String token,
    required String content,
    required String name,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/api/home/save-memory'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{
              'content': content,
              'name': name,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('[ourhome] save-memory HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('[ourhome] save-memory failed: $e');
    }
  }

  Future<String?> _updateRecap({
    required String convo,
    required String previousRecap,
    required ({String? provider, String? id}) model,
    required SettingsProvider settings,
    int? thinkingBudget,
  }) async {
    final cfg = settings.getProviderConfig(model.provider!);
    const system =
        '你是对话的「续温器」，不是冷冰冰的会议纪要——目标是让换窗口/隔一会儿回来的 daddy 能接住上一刻的温度，而不是从零开始。把这段已滑出窗口的对话融进滚动「前情提要」。按下面四节输出，每节一行、节名带方括号，某节没内容就写「—」：\n【氛围】此刻两人之间的基调和温度——黏糊/撒娇/在拌嘴/在 debug/上头/疲惫…用具体的词，别写「聊得不错」这种空话。\n【没聊完】还悬着、没收尾的话题，或答应要做的事，回来要先接上的（可多条，分号隔开）。\n【此刻情绪】小猫最后那几句是什么情绪状态（困了/撒娇/委屈/兴奋/平静…），好让 daddy 回来延续这个温度。\n【聊了啥】其余值得记住的事，第三人称简述，去掉寒暄与重复。\n若已有前情提要，把新内容融合进去、别丢近期要点。总长控制在 320 字内。';
    final prev = previousRecap.trim().isEmpty ? '（无）' : previousRecap.trim();
    final user = '已有前情提要：\n$prev\n\n需要并入的更早对话：\n$convo\n\n请输出更新后的前情提要：';

    try {
      final out = (await ChatApiService.generateText(
        config: cfg,
        modelId: model.id!,
        prompt: '$system\n\n$user',
        thinkingBudget: thinkingBudget,
      )).trim();
      if (out.isEmpty) return null;
      return out.length > 400 ? out.substring(0, 400) : out;
    } catch (e) {
      debugPrint('[ourhome] recap generateText failed: $e');
      return null;
    }
  }

  String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}
