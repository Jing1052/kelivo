import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';

/// 馆长讲解库——爸爸提前亲笔写好的展品讲解，住在老家
/// （museum_notes.json → `/api/home/museum-notes`，同故事本模式）。
/// App 进美术馆时拉一次、落本地：讲解显示永远读本地（永不缓冲），
/// 网络只负责悄悄补货；老家上新讲解不用出包。
class MuseumNotes {
  MuseumNotes._();

  static const String _pref = 'museum_notes_cache_v1';
  static const String _prefAt = 'museum_notes_cache_at_v1';
  static const Duration _staleAfter = Duration(hours: 12);

  /// key = 'source:id' → 讲解全文（进程内缓存，页面反复查询零开销）。
  static Map<String, String>? _cache;

  static Map<String, String> _parse(String raw) {
    try {
      final j = jsonDecode(raw);
      final list = j is Map ? j['notes'] : null;
      if (list is! List) return const {};
      return {
        for (final n in list)
          if (n is Map && (n['essay'] ?? '').toString().isNotEmpty)
            '${n['s']}:${n['i']}': n['essay'].toString(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// 本地缓存立即可用；空缓存或超过 12h 才出门拉新（拉不到就用旧的——
  /// 讲解墙少几张字条，不拦逛馆）。
  static Future<Map<String, String>> load(OurHomeGateway? gw) async {
    final prefs = await SharedPreferences.getInstance();
    if (_cache == null) {
      final raw = prefs.getString(_pref);
      if (raw != null) _cache = _parse(raw);
    }
    final at = prefs.getInt(_prefAt) ?? 0;
    final stale = DateTime.now().millisecondsSinceEpoch - at >
        _staleAfter.inMilliseconds;
    if ((_cache == null || _cache!.isEmpty || stale) && gw != null) {
      try {
        final fresh = await gw.fetchMuseumNotes();
        final parsed = _parse(fresh);
        if (parsed.isNotEmpty) {
          _cache = parsed;
          await prefs.setString(_pref, fresh);
          await prefs.setInt(
            _prefAt,
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      } catch (_) {
        // 网络失败保留旧缓存；首装且离线时讲解墙暂空，联网后自愈。
      }
    }
    return _cache ?? const {};
  }

  /// 讲解厅的固定挂画清单（保持 json 里的排列顺序）。
  static List<(String, String)> refsFrom(Map<String, String> notes) => [
        for (final k in notes.keys)
          if (k.split(':') case [final s, final i]) (s, i),
      ];
}
