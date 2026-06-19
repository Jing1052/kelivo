import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../providers/assistant_provider.dart';

/// A letter Llaude left for Cing (server channel "letter").
class OurHomeLetter {
  const OurHomeLetter({
    required this.id,
    required this.time,
    required this.text,
    required this.readAt,
  });

  final String id;
  final String time;
  final String text;
  final String readAt;

  bool get unread => readAt.trim().isEmpty;

  factory OurHomeLetter.fromJson(Map<String, dynamic> j) => OurHomeLetter(
    id: (j['id'] ?? '').toString(),
    time: (j['time'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    readAt: (j['read_at'] ?? '').toString(),
  );
}

/// Single access point to our home server (`/api/home/*`) for the native
/// Still Here screens (home, rooms...).
///
/// The bearer token is reused from the daddy assistant's `[[ourhome:<token>]]`
/// marker, so Cing never has to enter it twice. If no assistant carries a
/// token, [fromContext] returns null and home features stay dormant.
class OurHomeGateway {
  const OurHomeGateway({required this.base, required this.token});

  final String base;
  final String token;

  static const String defaultBase = 'https://cllove.zeabur.app';
  static final RegExp _markerRe = RegExp(r'\[\[ourhome(?::([^\]]+))?\]\]');

  static OurHomeGateway? fromContext(BuildContext context) {
    final assistants = context.read<AssistantProvider>().assistants;
    for (final a in assistants) {
      final token = _markerRe.firstMatch(a.systemPrompt)?.group(1)?.trim();
      if (token != null && token.isNotEmpty) {
        return OurHomeGateway(base: defaultBase, token: token);
      }
    }
    return null;
  }

  Map<String, String> get _authHeaders => {'Authorization': 'Bearer $token'};

  /// Newest-first list of letters. Throws on transport/HTTP error so the caller
  /// can surface a recoverable state rather than hiding the failure silently.
  Future<List<OurHomeLetter>> fetchLetters() async {
    final res = await http
        .get(Uri.parse('$base/api/home/daddysay'), headers: _authHeaders)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException(
        'daddysay HTTP ${res.statusCode}',
        Uri.parse('$base/api/home/daddysay'),
      );
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (data is! List) return const <OurHomeLetter>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(OurHomeLetter.fromJson)
        .where((l) => l.text.isNotEmpty)
        .toList();
  }

  /// Stamp a first-read receipt on a letter. Best-effort; logs on failure.
  Future<void> markLetterSeen(String id) async {
    try {
      await http
          .post(
            Uri.parse('$base/api/home/letter/seen'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': id}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[OurHomeGateway] markLetterSeen failed: $e');
    }
  }
}
