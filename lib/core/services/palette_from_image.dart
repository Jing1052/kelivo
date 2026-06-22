import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Extracts a representative "seed" color from an image's bytes, used to
/// generate a theme palette from a painting (design: Theme from Painting).
///
/// Heuristic: downscale, quantize colors into coarse buckets, then pick the
/// bucket with the highest (frequency × vividness), skipping near-black and
/// near-white so the seed actually carries the painting's character. Returns
/// null if the image can't be decoded.
Color? dominantColorFromBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // Downscale for speed; 64px wide is plenty for a dominant-color estimate.
  final im = decoded.width > 64 ? img.copyResize(decoded, width: 64) : decoded;

  // Bucket key -> [count, sumR, sumG, sumB].
  final buckets = <int, List<int>>{};
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final px = im.getPixel(x, y);
      final a = px.a.toInt();
      if (a < 128) continue; // skip transparent
      final r = px.r.toInt();
      final g = px.g.toInt();
      final b = px.b.toInt();
      // Quantize to 4 bits/channel (16 levels) -> 12-bit key.
      final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      final e = buckets.putIfAbsent(key, () => <int>[0, 0, 0, 0]);
      e[0]++;
      e[1] += r;
      e[2] += g;
      e[3] += b;
    }
  }
  if (buckets.isEmpty) return null;

  double bestScore = -1;
  Color? best;
  Color? fallback; // most frequent regardless of vividness
  int fallbackCount = -1;

  buckets.forEach((_, e) {
    final count = e[0];
    final r = e[1] ~/ count;
    final g = e[2] ~/ count;
    final b = e[3] ~/ count;
    final c = Color.fromARGB(255, r, g, b);
    final hsl = HSLColor.fromColor(c);

    if (count > fallbackCount) {
      fallbackCount = count;
      fallback = c;
    }

    // Skip near-black / near-white for the vivid pick.
    if (hsl.lightness < 0.12 || hsl.lightness > 0.92) return;
    // Frequency weighted by saturation so a vivid accent can win over a
    // large dull background, but sheer dominance still counts.
    final score = count * (0.25 + hsl.saturation);
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  });

  return best ?? fallback;
}
