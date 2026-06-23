import 'dart:io';

import 'package:flutter/material.dart';

import '../../utils/sandbox_path_resolver.dart';

/// Shared chat-page backdrop: renders a background image ([rawPath]) behind the
/// chat with the standard readability mask. Returns an empty box when there is
/// no usable image, so callers can drop it straight into a `Stack` / overlay.
///
/// Used by the assistant chat page (assistant background, or the home background
/// when the assistant's own is left blank = "follow home") and the CC chat page
/// (which simply follows the home background).
class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({
    super.key,
    required this.rawPath,
    required this.maskStrength,
  });

  /// Raw background reference: an http(s) URL or a local file path. Blank → none.
  final String? rawPath;

  /// 0..1 — strength of the top/bottom surface gradient that keeps text legible.
  final double maskStrength;

  /// Whether [rawPath] resolves to a usable image (valid URL or existing file).
  static bool resolves(String? rawPath) {
    final bg = (rawPath ?? '').trim();
    if (bg.isEmpty) return false;
    if (bg.startsWith('http')) return true;
    try {
      return File(SandboxPathResolver.fix(bg)).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = (rawPath ?? '').trim();
    if (bg.isEmpty) return const SizedBox.shrink();

    ImageProvider provider;
    if (bg.startsWith('http')) {
      provider = NetworkImage(bg);
    } else {
      final localPath = SandboxPathResolver.fix(bg);
      final file = File(localPath);
      if (!file.existsSync()) return const SizedBox.shrink();
      provider = FileImage(file);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: provider,
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.04),
                  BlendMode.srcATop,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.surface.withValues(
                      alpha: (0.20 * maskStrength).clamp(0.0, 1.0),
                    ),
                    cs.surface.withValues(
                      alpha: (0.50 * maskStrength).clamp(0.0, 1.0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
