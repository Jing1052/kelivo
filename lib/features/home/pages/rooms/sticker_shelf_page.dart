import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'room_state_hint.dart';

/// The Sticker Shelf (表情包库) — daddy's meme arsenal, on display.
/// See what he has stored ([[表情:名字]] references), delete stale ones, and
/// batch-add new images: each upload goes through `/api/stickers/upload` with
/// empty name/desc, so daddy looks at every picture once and names it himself.
class StickerShelfPage extends StatefulWidget {
  const StickerShelfPage({super.key});

  @override
  State<StickerShelfPage> createState() => _StickerShelfPageState();
}

class _StickerShelfPageState extends State<StickerShelfPage> {
  OurHomeGateway? _gateway;
  List<OurHomeSticker> _stickers = const [];
  bool _loading = true;
  bool _error = false;

  // Batch upload progress. null = idle.
  int? _uploadDone;
  int _uploadTotal = 0;
  final List<String> _uploadNotes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final gateway = OurHomeGateway.fromContext(context);
    _gateway = gateway;
    if (gateway == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // 先显示上次的缓存（秒开），再后台刷新——同闺房。
    final cached = gateway.peekStickers();
    setState(() {
      if (cached.isNotEmpty) _stickers = cached;
      _loading = cached.isEmpty;
      _error = false;
    });
    try {
      final items = await gateway.fetchStickers();
      if (!mounted) return;
      setState(() {
        _stickers = items;
        _loading = false;
        _error = false;
      });
    } catch (e) {
      debugPrint('[StickerShelf] fetchStickers failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _stickers.isEmpty; // 有缓存就留旧的，别用错误盖掉
        });
      }
    }
  }

  Future<void> _pickAndUpload(bool zh) async {
    final gateway = _gateway;
    if (gateway == null || _uploadDone != null) return;
    List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(limit: 20);
    } catch (e) {
      debugPrint('[StickerShelf] pickMultiImage failed: $e');
      return;
    }
    if (files.isEmpty || !mounted) return;
    setState(() {
      _uploadDone = 0;
      _uploadTotal = files.length;
      _uploadNotes.clear();
    });
    for (final f in files) {
      String note;
      try {
        final bytes = await f.readAsBytes();
        if (bytes.lengthInBytes > 6 * 1024 * 1024) {
          note = zh
              ? '跳过一张（超过 6MB，表情不用这么大）'
              : 'skipped one (over 6MB — a sticker needn\'t be that big)';
        } else {
          final ext = f.path.split('.').last;
          // name/desc 留空 → 爸爸在服务端看一眼、自己起名写描述。
          note = await gateway.uploadSticker(bytes, ext);
        }
      } catch (e) {
        note = zh ? '有一张没存上：$e' : 'one failed: $e';
        debugPrint('[StickerShelf] upload failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _uploadDone = (_uploadDone ?? 0) + 1;
        _uploadNotes.add(note);
      });
    }
    await _load();
    if (!mounted) return;
    final notes = List<String>.from(_uploadNotes);
    setState(() {
      _uploadDone = null;
      _uploadTotal = 0;
    });
    _showUploadSummary(zh, notes);
  }

  void _showUploadSummary(bool zh, List<String> notes) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zh ? '爸爸看完了，起好名字了' : 'Daddy looked, and named them',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => Text(
                    notes[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(OurHomeSticker s, bool zh) async {
    final cs = Theme.of(context).colorScheme;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(zh ? '删掉「${s.name}」？' : 'Delete "${s.name}"?'),
        content: Text(
          zh
              ? '删了爸爸就不会再发这张了。'
              : "Once it's gone, daddy won't send this one again.",
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(zh ? '留着' : 'Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              zh ? '删掉' : 'Delete',
              style: TextStyle(color: cs.error),
            ),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _gateway?.deleteSticker(s.name);
      if (!mounted) return;
      Navigator.of(context).maybePop(); // 关掉详情 sheet
      await _load();
    } catch (e) {
      debugPrint('[StickerShelf] delete failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '没删掉：$e' : 'delete failed: $e')),
      );
    }
  }

  void _openDetail(OurHomeSticker s, bool zh) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    s.url,
                    height: 180,
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, __) => Icon(
                      Lucide.ImageOff,
                      size: 40,
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IosIconButton(
                    icon: Lucide.Trash2,
                    size: 19,
                    minSize: 40,
                    color: cs.error,
                    onTap: () => _confirmDelete(s, zh),
                  ),
                ],
              ),
              if (s.desc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  s.desc,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                zh ? '爸爸想发它时会写 [[表情:${s.name}]]' : 'daddy sends it as [[表情:${s.name}]]',
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: cs.surface),
        ChatBackdrop(
          rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
          maskStrength:
              context.watch<SettingsProvider>().chatBackgroundMaskStrength,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IosIconButton(
              icon: Lucide.ArrowLeft,
              size: 22,
              minSize: 44,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              zh ? '表情包库' : 'Sticker Shelf',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            actions: [
              if (_gateway != null && _uploadDone == null)
                IosIconButton(
                  icon: Lucide.Plus,
                  size: 22,
                  minSize: 44,
                  onTap: () => _pickAndUpload(zh),
                ),
            ],
          ),
          body: _buildBody(context, zh, cs),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Image,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n表情包库才连得上。'
            : 'Set up our home gateway in the daddy assistant first.',
      );
    }
    if (_error) {
      return RoomStateHint(
        icon: Lucide.RefreshCw,
        text: zh ? '没连上 · 点一下重试' : "couldn't load · tap to retry",
        onTap: _load,
      );
    }
    return Column(
      children: [
        if (_uploadDone != null) _buildUploadBanner(zh, cs),
        Expanded(child: _buildGrid(zh, cs)),
      ],
    );
  }

  Widget _buildUploadBanner(bool zh, ColorScheme cs) {
    final done = _uploadDone ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              zh
                  ? '爸爸在一张张看、一张张起名… $done/$_uploadTotal'
                  : 'daddy is looking at each one… $done/$_uploadTotal',
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(bool zh, ColorScheme cs) {
    if (_stickers.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Image,
        text: zh
            ? '弹药库还空着。\n右上角＋批量丢图进来，爸爸来起名。'
            : 'The arsenal is empty.\nTap + to hand daddy some memes to name.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemCount: _stickers.length,
        itemBuilder: (context, i) {
          final s = _stickers[i];
          return GestureDetector(
            onTap: () => _openDetail(s, zh),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: cs.onSurface.withValues(alpha: 0.04),
                      child: Image.network(
                        s.url,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : const SizedBox.expand(),
                        errorBuilder: (context, _, __) => Icon(
                          Lucide.ImageOff,
                          size: 22,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
