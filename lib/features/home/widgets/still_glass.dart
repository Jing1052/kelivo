import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';

/// Fill colour of the home "glass" card — soft translucent white whose opacity
/// follows the `homeCardOpacity` setting. Single source of truth shared by the
/// home dashboard and the room pages, so they read identically over the
/// background photo.
Color stillGlassFill(BuildContext c) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  final op = c.select<SettingsProvider, double>((s) => s.homeCardOpacity);
  return Colors.white.withValues(alpha: dark ? op * 0.34 : op);
}

/// Hairline border colour for the glass card.
Color stillGlassLine(BuildContext c) {
  final dark = Theme.of(c).brightness == Brightness.dark;
  return dark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.55);
}

/// A frosted card tile: optionally blurs the background photo behind it, soft
/// translucent fill, hairline border. Used on the home dashboard and reused on
/// the room pages so everything reads the same over the wallpaper.
///
/// [blur] defaults to the `homeCardBlur` setting. Pass `false` for items in a
/// long scrolling list (e.g. diary entries) to avoid stacking many
/// `BackdropFilter`s — the translucent fill alone keeps text readable.
class StillGlass extends StatelessWidget {
  const StillGlass({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.radius = 22,
    this.blur,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool? blur;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final useBlur =
        blur ?? context.select<SettingsProvider, bool>((s) => s.homeCardBlur);
    final card = IosCardPress(
      borderRadius: br,
      baseColor: stillGlassFill(context),
      border: Border.all(color: stillGlassLine(context), width: 1),
      padding: padding,
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
    return ClipRRect(
      borderRadius: br,
      child: useBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: card,
            )
          : card,
    );
  }
}
