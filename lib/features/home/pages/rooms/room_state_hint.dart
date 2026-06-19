import 'package:flutter/material.dart';

/// Shared empty / error / no-gateway placeholder for native room pages.
/// Centered icon + message; optionally tappable (e.g. retry).
class RoomStateHint extends StatelessWidget {
  const RoomStateHint({
    super.key,
    required this.icon,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: cs.onSurface.withValues(alpha: 0.28)),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: onTap == null
            ? child
            : GestureDetector(onTap: onTap, child: child),
      ),
    );
  }
}
