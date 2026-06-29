import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Deep-link helpers for opening songs in NetEase Cloud Music.
///
/// We don't store NetEase song ids yet, so we deep-link to NetEase's mobile
/// search for "title artist". On iOS this routes to the NetEase app via its
/// universal link when installed, otherwise it falls back to the mobile web.
Uri neteaseSearchUri(String title, String artist) {
  final q = Uri.encodeComponent('$title $artist'.trim());
  return Uri.parse('https://music.163.com/#/search/m/?s=$q');
}

/// Open [title]/[artist] in NetEase Cloud Music. Shows a SnackBar if nothing
/// can handle the link. Safe to call from any widget with a [BuildContext].
Future<void> openSongInNetease(
  BuildContext context, {
  required String title,
  required String artist,
}) async {
  final uri = neteaseSearchUri(title, artist);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return;
  } catch (_) {
    try {
      if (await launchUrl(uri)) return;
    } catch (_) {}
  }
  messenger?.showSnackBar(
    SnackBar(
      content: Text(zh ? '打不开网易云音乐' : 'Could not open NetEase Music'),
    ),
  );
}
