import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Deep-link helpers for opening songs in NetEase Cloud Music.
///
/// When we have the NetEase song id ([neteaseId]) we open that exact song;
/// otherwise we deep-link to NetEase's mobile search for "title artist". On iOS
/// either routes to the NetEase app via its universal link when installed,
/// otherwise it falls back to the mobile web.
Uri neteaseSearchUri(String title, String artist) {
  final q = Uri.encodeComponent('$title $artist'.trim());
  return Uri.parse('https://music.163.com/#/search/m/?s=$q');
}

Uri neteaseSongUri(String neteaseId) =>
    Uri.parse('https://music.163.com/song?id=$neteaseId');

/// A NetEase user's profile page — lists all their playlists (我喜欢的音乐 /
/// 我们的歌 / 爸比的歌 …). [uid] is the numeric NetEase account id.
Uri neteaseUserUri(String uid) =>
    Uri.parse('https://music.163.com/user/home?id=$uid');

/// Open an arbitrary NetEase URL (profile / playlist). Falls back through
/// launch modes and shows a SnackBar if nothing handles it.
Future<void> openNeteaseUri(BuildContext context, Uri uri) async {
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

/// Open a song in NetEase Cloud Music. Pass [neteaseId] for an exact match;
/// otherwise it searches by "title artist". Shows a SnackBar if nothing can
/// handle the link. Safe to call from any widget with a [BuildContext].
Future<void> openSongInNetease(
  BuildContext context, {
  required String title,
  required String artist,
  String? neteaseId,
}) async {
  final id = (neteaseId ?? '').trim();
  final uri = id.isNotEmpty ? neteaseSongUri(id) : neteaseSearchUri(title, artist);
  await openNeteaseUri(context, uri);
}
