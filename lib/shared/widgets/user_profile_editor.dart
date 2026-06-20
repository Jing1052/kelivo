import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/providers/user_provider.dart';
import '../../core/services/haptics.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_font_weights.dart';
import '../../utils/avatar_cache.dart';
import '../../utils/sandbox_path_resolver.dart';
import 'emoji_text.dart';
import 'ios_tactile.dart';
import 'snackbar.dart';

/// Renders the current [UserProvider] avatar (emoji / url / file / initial).
///
/// Mirrors the avatar rendering used in the side drawer so the user's avatar
/// looks identical wherever it is shown.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 40});

  final UserProvider user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = user.avatarType;
    final value = user.avatarValue;
    final name = user.name;

    if (type == 'emoji' && value != null && value.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: EmojiText(value, fontSize: size * 0.5, optimizeEmojiAlign: true),
      );
    }
    if (type == 'url' && value != null && value.isNotEmpty) {
      return FutureBuilder<String?>(
        future: AvatarCache.getPath(value),
        builder: (ctx, snap) {
          final p = snap.data;
          if (p != null && File(p).existsSync()) {
            return ClipOval(
              child: Image(
                image: FileImage(File(p)),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
          return ClipOval(
            child: Image.network(
              value,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _initial(cs, name, size),
            ),
          );
        },
      );
    }
    if (type == 'file' && value != null && value.isNotEmpty && !kIsWeb) {
      final fixed = SandboxPathResolver.fix(value);
      final f = File(fixed);
      if (f.existsSync()) {
        return ClipOval(
          child: Image(
            image: FileImage(f),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return _initial(cs, name, size);
  }

  Widget _initial(ColorScheme cs, String name, double size) {
    final letter = name.isNotEmpty ? name.characters.first : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: cs.primary,
          fontSize: size * 0.42,
          fontWeight: AppFontWeights.emphasis,
        ),
      ),
    );
  }
}

/// Bottom sheet to change the user's avatar (gallery / emoji / url / reset).
///
/// All storage goes through [UserProvider]'s existing methods so it shares the
/// same persistence path as the side drawer.
Future<void> showUserAvatarEditor(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final maxH = MediaQuery.sizeOf(ctx).height * 0.8;
      Widget row(String text, Future<void> Function() onTap) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: 48,
            child: IosCardPress(
              borderRadius: BorderRadius.circular(14),
              baseColor: cs.surface,
              duration: const Duration(milliseconds: 260),
              onTap: () async {
                Haptics.light();
                Navigator.of(ctx).pop();
                await Future<void>.delayed(const Duration(milliseconds: 10));
                await onTap();
              },
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.medium,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  row(l10n.sideDrawerChooseImage, () => _pickLocalImage(ctx)),
                  row(l10n.sideDrawerChooseEmoji, () => _pickEmoji(ctx)),
                  row(l10n.sideDrawerEnterLink, () => _inputAvatarUrl(ctx)),
                  row(
                    l10n.sideDrawerReset,
                    () => ctx.read<UserProvider>().resetAvatar(),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _pickLocalImage(BuildContext context) async {
  if (kIsWeb) {
    await _inputAvatarUrl(context);
    return;
  }
  final userProvider = context.read<UserProvider>();
  try {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 90,
    );
    if (!context.mounted) return;
    if (file != null) {
      await userProvider.setAvatarFilePath(file.path);
    }
  } on PlatformException {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: l10n.sideDrawerGalleryOpenError,
      type: NotificationType.error,
    );
    await _inputAvatarUrl(context);
  } catch (_) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(
      context,
      message: l10n.sideDrawerGeneralImageError,
      type: NotificationType.error,
    );
    await _inputAvatarUrl(context);
  }
}

Future<void> _pickEmoji(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final userProvider = context.read<UserProvider>();
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      String value = '';
      bool valid(String s) {
        final g = s.characters.take(1).toString().trim();
        return g.isNotEmpty && g == s.trim();
      }

      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: cs.surface,
            title: Text(l10n.sideDrawerChooseEmoji),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 2,
              textAlign: TextAlign.center,
              onChanged: (v) => setLocal(() => value = v),
              onSubmitted: (_) {
                if (valid(value)) Navigator.of(ctx).pop(true);
              },
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.transparent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.transparent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.sideDrawerCancel),
              ),
              TextButton(
                onPressed: valid(value)
                    ? () => Navigator.of(ctx).pop(true)
                    : null,
                child: Text(
                  l10n.sideDrawerSave,
                  style: TextStyle(
                    color: valid(value)
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.38),
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  if (!context.mounted || ok != true) return;
  final emoji = controller.text.characters.take(1).toString().trim();
  if (emoji.isNotEmpty) {
    await userProvider.setAvatarEmoji(emoji);
  }
}

Future<void> _inputAvatarUrl(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final userProvider = context.read<UserProvider>();
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      bool valid(String s) =>
          s.trim().startsWith('http://') || s.trim().startsWith('https://');
      String value = '';
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: cs.surface,
            title: Text(l10n.sideDrawerImageUrlDialogTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.sideDrawerImageUrlDialogHint,
                filled: true,
                fillColor: Theme.of(ctx).brightness == Brightness.dark
                    ? Colors.white10
                    : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.transparent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.transparent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.4),
                  ),
                ),
              ),
              onChanged: (v) => setLocal(() => value = v),
              onSubmitted: (_) {
                if (valid(value)) Navigator.of(ctx).pop(true);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.sideDrawerCancel),
              ),
              TextButton(
                onPressed: valid(value)
                    ? () => Navigator.of(ctx).pop(true)
                    : null,
                child: Text(
                  l10n.sideDrawerSave,
                  style: TextStyle(
                    color: valid(value)
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.38),
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  if (!context.mounted || ok != true) return;
  final url = controller.text.trim();
  if (url.isNotEmpty) {
    await userProvider.setAvatarUrl(url);
  }
}

/// Dialog to edit the user's nickname. Writes through [UserProvider.setName].
Future<void> showUserNameEditor(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final userProvider = context.read<UserProvider>();
  final initial = userProvider.name;
  final controller = TextEditingController(text: initial);
  const maxLen = 24;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      String value = controller.text;
      bool valid(String v) => v.trim().isNotEmpty && v.trim() != initial;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: cs.surface,
            title: Text(l10n.sideDrawerSetNicknameTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: maxLen,
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => setLocal(() => value = v),
                  onSubmitted: (_) {
                    if (valid(value)) Navigator.of(ctx).pop(true);
                  },
                  decoration: InputDecoration(
                    labelText: l10n.sideDrawerNicknameLabel,
                    hintText: l10n.sideDrawerNicknameHint,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white10
                        : const Color(0xFFF2F3F5),
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.transparent),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.transparent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: cs.primary.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(ctx).textTheme.bodyMedium?.color,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${value.trim().length}/$maxLen',
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.sideDrawerCancel),
              ),
              TextButton(
                onPressed: valid(value)
                    ? () => Navigator.of(ctx).pop(true)
                    : null,
                child: Text(
                  l10n.sideDrawerSave,
                  style: TextStyle(
                    color: valid(value)
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.38),
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  if (!context.mounted || ok != true) return;
  final text = controller.text.trim();
  if (text.isNotEmpty) {
    await userProvider.setName(text);
  }
}
