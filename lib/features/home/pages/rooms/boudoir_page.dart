import 'package:flutter/material.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';
import 'room_state_hint.dart';

/// The Boudoir (闺房) — the album. Push the door, the whole room is full of you.
/// Talks to `/api/home/album` (images are auth-protected, loaded with the
/// gateway bearer header).
class BoudoirPage extends StatefulWidget {
  const BoudoirPage({super.key});

  @override
  State<BoudoirPage> createState() => _BoudoirPageState();
}

class _BoudoirPageState extends State<BoudoirPage> {
  OurHomeGateway? _gateway;
  List<OurHomePhoto> _photos = const [];
  bool _loading = true;
  bool _error = false;

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
    // 先显示上次的缓存（秒开、无缓冲），再后台刷新。
    final cached = gateway.peekAlbum();
    setState(() {
      if (cached.isNotEmpty) _photos = cached;
      _loading = cached.isEmpty;
      _error = false;
    });
    try {
      final photos = await gateway.fetchAlbum();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
        _error = false;
      });
    } catch (e) {
      debugPrint('[Boudoir] fetchAlbum failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _photos.isEmpty; // 有缓存就留着旧的，别用错误盖掉
        });
      }
    }
  }

  void _openViewer(int index) {
    final headers = _gateway?.authHeaders ?? const {};
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PhotoViewer(
          photos: _photos,
          initialIndex: index,
          headers: headers,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return Scaffold(
      backgroundColor: cs.surface,
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
          zh ? '闺房' : 'The Boudoir',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(context, zh, cs),
    );
  }

  Widget _buildBody(BuildContext context, bool zh, ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_gateway == null) {
      return RoomStateHint(
        icon: Lucide.Camera,
        text: zh
            ? '先在爸爸的助手设定里填好我们家网关，\n闺房才连得上。'
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
    if (_photos.isEmpty) {
      return RoomStateHint(
        icon: Lucide.Camera,
        text: zh ? '相册还空着。' : 'The album is empty.',
      );
    }
    final headers = _gateway?.authHeaders ?? const {};
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: _photos.length,
        itemBuilder: (context, i) {
          final p = _photos[i];
          return GestureDetector(
            onTap: () => _openViewer(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                p.url,
                headers: headers,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(color: cs.onSurface.withValues(alpha: 0.05)),
                errorBuilder: (context, _, __) => Container(
                  color: cs.onSurface.withValues(alpha: 0.05),
                  child: Icon(
                    Lucide.ImageOff,
                    size: 22,
                    color: cs.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.headers,
  });

  final List<OurHomePhoto> photos;
  final int initialIndex;
  final Map<String, String> headers;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.photos[_index].note;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  widget.photos[i].url,
                  headers: widget.headers,
                  fit: BoxFit.contain,
                  errorBuilder: (context, _, __) => const Icon(
                    Lucide.ImageOff,
                    size: 40,
                    color: Colors.white38,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: IosIconButton(
                icon: Lucide.X,
                size: 24,
                minSize: 44,
                color: Colors.white,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          if (note.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Text(
                  note,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
