import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../core/services/ourhome/ourhome_gateway.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// How the reader lays the book out: a continuous vertical [scroll] (default,
/// ScrollablePositionedList) or left/right [page] turning (PageView). Persisted
/// globally so her choice sticks across books and launches.
enum BookReaderMode { scroll, page }

/// How many paragraphs go on one page in page-turning mode. A simple,
/// predictable first-version pagination — fixed count per screen, no height
/// estimation yet (precision to be tuned later).
const int _kParasPerPage = 6;

/// A paper-toned reader for one whole-text book on the "一起读" shelf.
///
/// Loads `/api/home/reading/book/{id}` (entry + paragraphs + chapters + daddy's
/// margin notes), renders the body as a lazily-built scrolling list so long
/// books stay smooth, lets her jump by chapter, lights a 🌙 at the end of any
/// paragraph daddy left a note on, and throttle-saves reading progress as she
/// scrolls. Opening restores her from the last-saved progress fraction.
class BookReaderPage extends StatefulWidget {
  const BookReaderPage({
    super.key,
    required this.gateway,
    required this.bookId,
    required this.title,
  });

  final OurHomeGateway gateway;
  final String bookId;
  final String title;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  // Paper tones — warm off-white / aged paper, never pure white.
  static const Color _paperLight = Color(0xFFF4ECDD);
  static const Color _inkLight = Color(0xFF3A322A);
  static const Color _paperDark = Color(0xFF1E1B17);
  static const Color _inkDark = Color(0xFFCFC4B0);

  static const String _modePrefKey = 'book_reader_mode';

  final ItemScrollController _scrollCtrl = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  PageController? _pageCtrl;

  ReadingBook? _book;
  Map<int, ReadingNote> _notesByPara = const {};
  bool _loading = true;
  bool _error = false;

  // Layout mode (scroll vs. page-turn). Loaded from prefs in initState.
  BookReaderMode _mode = BookReaderMode.scroll;

  // Throttled progress save: track the latest fraction + a pending timer.
  double _progress = 0;
  int _curChapter = 0;
  int _curPage = 0;
  Timer? _saveTimer;
  double _lastSavedProgress = -1;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onScroll);
    _loadMode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onScroll);
    _saveTimer?.cancel();
    _pageCtrl?.dispose();
    // Flush the latest progress on the way out (best-effort, fire-and-forget).
    if (_book != null &&
        _book!.paragraphs.isNotEmpty &&
        _progress != _lastSavedProgress) {
      widget.gateway.saveReadingProgress(
        widget.bookId,
        _progress,
        chapter: _curChapter,
      );
    }
    super.dispose();
  }

  Future<void> _loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final raw = prefs.getString(_modePrefKey);
    final mode = raw == 'page' ? BookReaderMode.page : BookReaderMode.scroll;
    if (mode != _mode) setState(() => _mode = mode);
  }

  // ---- Page-mode pagination (fixed paragraphs-per-page, first version) ----
  int get _pageCount {
    final total = _book?.paragraphs.length ?? 0;
    if (total == 0) return 0;
    return (total + _kParasPerPage - 1) ~/ _kParasPerPage;
  }

  int _pageForPara(int para) => para ~/ _kParasPerPage;
  int _firstParaOfPage(int page) => page * _kParasPerPage;

  Future<void> _load() async {
    if (!mounted) return;
    // 秒开：show the last-opened copy from on-device cache immediately (no
    // spinner), then refresh from the network in the background below.
    final cached = widget.gateway.peekBookDetail(widget.bookId);
    if (cached != null && cached.paragraphs.isNotEmpty) {
      _applyBook(cached, restore: true);
    } else {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final book = await widget.gateway.fetchBookDetail(widget.bookId);
      if (!mounted) return;
      // Only restore position from the freshly-fetched progress when we didn't
      // already restore off the cache (don't yank her away from where she is).
      _applyBook(book, restore: cached == null);
    } catch (e) {
      debugPrint('[BookReader] load failed: $e');
      if (mounted && _book == null) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _applyBook(ReadingBook book, {required bool restore}) {
    final notes = <int, ReadingNote>{for (final n in book.notes) n.para: n};
    setState(() {
      _book = book;
      _notesByPara = notes;
      _loading = false;
      _error = false;
    });
    if (restore) _restorePosition(book);
  }

  void _restorePosition(ReadingBook book) {
    final total = book.paragraphs.length;
    if (total == 0) return;
    final frac = book.entry.progress.clamp(0.0, 1.0);
    final index = (frac * total).floor().clamp(0, total - 1);
    if (index <= 0) return;
    _progress = frac;
    _curChapter = _chapterIndexForPara(book, index);
    _curPage = _pageForPara(index);
    // Jump after the first frame so the list / pager is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mode == BookReaderMode.scroll) {
        if (_scrollCtrl.isAttached) {
          _scrollCtrl.jumpTo(index: index);
        }
      } else {
        _pageCtrl?.jumpToPage(_curPage);
      }
    });
  }

  Future<void> _toggleMode() async {
    final next = _mode == BookReaderMode.scroll
        ? BookReaderMode.page
        : BookReaderMode.scroll;
    Haptics.soft();
    // Carry the current reading position across the switch.
    final book = _book;
    final para = (book != null && book.paragraphs.isNotEmpty)
        ? (_progress * (book.paragraphs.length - 1)).round().clamp(
            0,
            book.paragraphs.length - 1,
          )
        : 0;
    setState(() {
      _mode = next;
      _curPage = _pageForPara(para);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modePrefKey, next == BookReaderMode.page ? 'page' : 'scroll');
    // Land on the same paragraph in the new layout after it's built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (next == BookReaderMode.scroll) {
        if (_scrollCtrl.isAttached) _scrollCtrl.jumpTo(index: para);
      } else {
        _pageCtrl?.jumpToPage(_curPage);
      }
    });
  }

  void _onScroll() {
    if (_mode != BookReaderMode.scroll) return;
    final book = _book;
    if (book == null) return;
    final total = book.paragraphs.length;
    if (total == 0) return;
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    // Topmost visible paragraph index.
    final first = positions
        .where((p) => p.itemTrailingEdge > 0)
        .fold<int>(total, (m, p) => p.index < m ? p.index : m);
    final idx = first.clamp(0, total - 1);
    final frac = total <= 1 ? 1.0 : (idx / (total - 1));
    _progress = frac;
    _curChapter = _chapterIndexForPara(book, idx);
    if (mounted) {
      setState(() {}); // refresh the header percentage
    }
    _scheduleSave();
  }

  void _onPageChanged(int page) {
    final book = _book;
    if (book == null) return;
    final total = book.paragraphs.length;
    if (total == 0) return;
    _curPage = page;
    final idx = _firstParaOfPage(page).clamp(0, total - 1);
    final frac = total <= 1 ? 1.0 : (idx / (total - 1));
    _progress = frac;
    _curChapter = _chapterIndexForPara(book, idx);
    if (mounted) {
      setState(() {}); // refresh the header percentage
    }
    _scheduleSave();
  }

  int _chapterIndexForPara(ReadingBook book, int para) {
    var ci = 0;
    for (var i = 0; i < book.chapters.length; i++) {
      if (book.chapters[i].para <= para) {
        ci = i;
      } else {
        break;
      }
    }
    return ci;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      if ((_progress - _lastSavedProgress).abs() < 0.001) return;
      _lastSavedProgress = _progress;
      widget.gateway.saveReadingProgress(
        widget.bookId,
        _progress,
        chapter: _curChapter,
      );
    });
  }

  void _openChapters(bool zh) {
    final book = _book;
    if (book == null || book.chapters.isEmpty) return;
    Haptics.soft();
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? _paperDark : _paperLight;
    final ink = dark ? _inkDark : _inkLight;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Icon(Lucide.ListTree, size: 18, color: ink.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Text(
                        zh ? '目录' : 'Chapters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: book.chapters.length,
                    itemBuilder: (c, i) {
                      final ch = book.chapters[i];
                      final on = i == _curChapter;
                      return IosCardPress(
                        baseColor: Colors.transparent,
                        borderRadius: BorderRadius.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 13,
                        ),
                        onTap: () {
                          Navigator.of(c).pop();
                          if (_mode == BookReaderMode.scroll) {
                            if (_scrollCtrl.isAttached) {
                              _scrollCtrl.scrollTo(
                                index: ch.para,
                                duration: const Duration(milliseconds: 320),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          } else {
                            _pageCtrl?.animateToPage(
                              _pageForPara(ch.para),
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                ch.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'serif',
                                  fontSize: 15,
                                  height: 1.35,
                                  fontWeight:
                                      on ? FontWeight.w700 : FontWeight.w400,
                                  color: on
                                      ? cs.primary
                                      : ink.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                            if (on)
                              Icon(Lucide.Check, size: 16, color: cs.primary),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openNote(ReadingNote note, bool zh) {
    Haptics.light();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? _paperDark : _paperLight;
    final ink = dark ? _inkDark : _inkLight;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            18 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🌙', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    zh ? '爸爸在这里想对你说' : 'Daddy left this here',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                note.note,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 16,
                  height: 1.7,
                  color: ink,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = dark ? _paperDark : _paperLight;
    final ink = dark ? _inkDark : _inkLight;
    final book = _book;
    final pct = (_progress * 100).round();

    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: ink),
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          size: 22,
          minSize: 44,
          color: ink,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            if (book != null && book.paragraphs.isNotEmpty)
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 11,
                  color: ink.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (book != null && book.paragraphs.isNotEmpty)
            IosIconButton(
              // Scroll mode shows the "switch to pages" glyph and vice-versa.
              icon: _mode == BookReaderMode.scroll
                  ? Lucide.BookOpen
                  : Lucide.FileText,
              size: 20,
              minSize: 44,
              color: ink,
              onTap: _toggleMode,
            ),
          if (book != null && book.chapters.length > 1)
            IosIconButton(
              icon: Lucide.ListTree,
              size: 21,
              minSize: 44,
              color: ink,
              onTap: () => _openChapters(zh),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: _buildBody(zh, ink),
    );
  }

  Widget _buildBody(bool zh, Color ink) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2.4, color: ink),
      );
    }
    if (_error) {
      return RoomStateHintReader(
        icon: Lucide.RefreshCw,
        text: zh ? '没打开 · 点一下重试' : "couldn't open · tap to retry",
        ink: ink,
        onTap: _load,
      );
    }
    final book = _book;
    if (book == null || book.paragraphs.isEmpty) {
      return RoomStateHintReader(
        icon: Lucide.BookOpen,
        text: zh ? '这本书是空的。' : 'This book is empty.',
        ink: ink,
      );
    }
    if (_mode == BookReaderMode.page) {
      return _buildPager(book, ink);
    }
    return ScrollablePositionedList.builder(
      itemScrollController: _scrollCtrl,
      itemPositionsListener: _positions,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
      itemCount: book.paragraphs.length,
      itemBuilder: (context, i) => _paragraph(book, i, ink),
    );
  }

  /// Left/right page-turning layout: paragraphs are chunked into fixed-size
  /// pages (first version — no per-page height fitting yet), each page its own
  /// scroll view so an over-full page still reads. Created lazily here so the
  /// controller starts on the restored page.
  Widget _buildPager(ReadingBook book, Color ink) {
    final pages = _pageCount;
    _pageCtrl ??= PageController(initialPage: _curPage.clamp(0, pages - 1));
    final total = book.paragraphs.length;
    return PageView.builder(
      controller: _pageCtrl,
      itemCount: pages,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, page) {
        final start = _firstParaOfPage(page);
        final end = (start + _kParasPerPage).clamp(0, total);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = start; i < end; i++) _paragraph(book, i, ink),
            ],
          ),
        );
      },
    );
  }

  Widget _paragraph(ReadingBook book, int i, Color ink) {
    final text = book.paragraphs[i];
    final note = _notesByPara[i];
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    // A chapter-heading paragraph is rendered bigger/centered.
    final isHeading = book.chapters.any((c) => c.para == i) && text.length <= 30;

    final bodyStyle = TextStyle(
      fontFamily: 'serif',
      fontSize: isHeading ? 19 : 16.5,
      height: isHeading ? 1.5 : 1.85,
      fontWeight: isHeading ? FontWeight.w700 : FontWeight.w400,
      color: ink,
    );

    final paragraph = Padding(
      padding: EdgeInsets.only(
        top: isHeading ? 26 : 0,
        bottom: isHeading ? 12 : 18,
      ),
      child: Text(
        text,
        textAlign: isHeading ? TextAlign.center : TextAlign.start,
        style: bodyStyle,
      ),
    );

    if (note == null) return paragraph;

    // Paragraph with a 🌙 margin note: tap the moon to read daddy's words.
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: isHeading ? 26 : 0, bottom: 6),
            child: Text(
              text,
              textAlign: isHeading ? TextAlign.center : TextAlign.start,
              style: bodyStyle,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openNote(note, zh),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🌙', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(
                  zh ? '爸爸的话' : "daddy's note",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: ink.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A paper-toned empty/error placeholder for the reader (its own copy so the
/// ink colour matches the warm page instead of the app theme's onSurface).
class RoomStateHintReader extends StatelessWidget {
  const RoomStateHintReader({
    super.key,
    required this.icon,
    required this.text,
    required this.ink,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 46, color: ink.withValues(alpha: 0.3)),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: ink.withValues(alpha: 0.55),
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
