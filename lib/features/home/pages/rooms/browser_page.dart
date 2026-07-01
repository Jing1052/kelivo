import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// 窗 (The Window) — a built-in, navigable web browser room. Opens any URL
/// inside the app via a WebView, with an address bar, back/forward/reload,
/// load progress, a desktop/mobile user-agent toggle, and a JS haptic bridge
/// so pages can trigger native haptics through a global `haptic(style)` helper.
///
/// Uses the official `webview_flutter` (WKWebView on iOS, WebView on Android),
/// same as the Wander room — one webview stack across the home.
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, this.initialUrl});

  /// Optional URL to open on launch. When null, the room opens blank with a
  /// hint prompting the user to type a URL.
  final String? initialUrl;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  // iPhone Safari UA (mobile, default) / Mac Safari UA (desktop mode).
  static const String _mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
      'Mobile/15E148 Safari/604.1';
  static const String _desktopUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

  // Injected on page start so any page can call `haptic('light'|'medium'
  // |'heavy'|'soft'|'rigid')`. Routes to the native channel when present,
  // otherwise degrades to the Web Vibration API.
  static const String _hapticShim =
      "window.haptic=function(s){try{if(window.HapticBridge){"
      "HapticBridge.postMessage(s||'medium');}else if(navigator.vibrate){"
      "navigator.vibrate(s==='light'?5:s==='heavy'?20:10);}}catch(e){}};";

  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  bool _desktopMode = false;
  bool _isLoading = false;
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _currentUrl = '';

  bool get _hasPage =>
      _currentUrl.isNotEmpty && !_currentUrl.startsWith('about:blank');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_mobileUa)
      ..addJavaScriptChannel('HapticBridge', onMessageReceived: _onHaptic)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100.0);
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _currentUrl = url;
              _syncUrlField();
            });
            _controller.runJavaScript(_hapticShim);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _currentUrl = url;
              _syncUrlField();
            });
            await _refreshNavState();
          },
          onWebResourceError: (err) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            const allowed = {'http', 'https', 'about', 'data', 'file'};
            if (uri != null &&
                uri.scheme.isNotEmpty &&
                !allowed.contains(uri.scheme)) {
              // Block non-web schemes (e.g. app deep links) instead of letting
              // the WebView hand off to an external app unexpectedly.
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    final initial = widget.initialUrl?.trim();
    if (initial != null && initial.isNotEmpty) {
      _urlController.text = initial;
      _controller.loadRequest(Uri.parse(_normalize(initial)));
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _onHaptic(JavaScriptMessage message) {
    switch (message.message) {
      case 'light':
      case 'soft':
        Haptics.light();
        break;
      case 'heavy':
      case 'rigid':
        Haptics.heavy();
        break;
      default:
        Haptics.medium();
    }
  }

  // Adds an https:// scheme when the user typed a bare host.
  String _normalize(String raw) {
    final s = raw.trim();
    if (s.contains('://')) return s;
    return 'https://$s';
  }

  void _submitUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return;
    _urlFocus.unfocus();
    _controller.loadRequest(Uri.parse(_normalize(s)));
  }

  Future<void> _toggleDesktop() async {
    setState(() => _desktopMode = !_desktopMode);
    Haptics.light();
    await _controller.setUserAgent(_desktopMode ? _desktopUa : _mobileUa);
    await _controller.reload();
  }

  Future<void> _refreshNavState() async {
    final back = await _controller.canGoBack();
    final fwd = await _controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _canGoForward = fwd;
    });
  }

  void _syncUrlField() {
    // Don't fight the user while they're editing the address bar.
    if (_urlFocus.hasFocus) return;
    if (_hasPage) _urlController.text = _currentUrl;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && _canGoBack) {
          await _controller.goBack();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: cs.surface),
          ChatBackdrop(
            rawPath: context.watch<SettingsProvider>().homeBackgroundActive,
            maskStrength: context
                .watch<SettingsProvider>()
                .chatBackgroundMaskStrength,
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
                zh ? '窗' : 'The Window',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                IosIconButton(
                  icon: Lucide.Monitor,
                  minSize: 44,
                  color: _desktopMode
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.6),
                  semanticLabel: _desktopMode
                      ? (zh ? '切换到移动版' : 'Switch to mobile site')
                      : (zh ? '切换到桌面版' : 'Switch to desktop site'),
                  onTap: _toggleDesktop,
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  _buildToolbar(context, zh, cs),
                  SizedBox(
                    height: 2,
                    child: _isLoading
                        ? LinearProgressIndicator(
                            value: _progress == 0 ? null : _progress,
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            color: cs.primary,
                          )
                        : null,
                  ),
                  Expanded(child: _buildWebView(context, zh, cs)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool zh, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          IosIconButton(
            icon: Lucide.ChevronLeft,
            minSize: 40,
            enabled: _canGoBack,
            semanticLabel: zh ? '后退' : 'Back',
            onTap: () {
              Haptics.light();
              _controller.goBack();
            },
          ),
          IosIconButton(
            icon: Lucide.ChevronRight,
            minSize: 40,
            enabled: _canGoForward,
            semanticLabel: zh ? '前进' : 'Forward',
            onTap: () {
              Haptics.light();
              _controller.goForward();
            },
          ),
          const SizedBox(width: 4),
          Expanded(child: _buildUrlField(context, zh, cs)),
        ],
      ),
    );
  }

  Widget _buildUrlField(BuildContext context, bool zh, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.only(left: 12, right: 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              focusNode: _urlFocus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: zh ? '输入网址' : 'Enter a URL',
              ),
              onSubmitted: _submitUrl,
            ),
          ),
          _isLoading
              ? IosIconButton(
                  icon: Lucide.X,
                  size: 16,
                  minSize: 36,
                  semanticLabel: zh ? '停止' : 'Stop',
                  onTap: () => _controller.loadRequest(Uri.parse('about:blank')),
                )
              : IosIconButton(
                  icon: Lucide.RotateCw,
                  size: 16,
                  minSize: 36,
                  semanticLabel: zh ? '刷新' : 'Reload',
                  onTap: () {
                    Haptics.light();
                    _controller.reload();
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildWebView(BuildContext context, bool zh, ColorScheme cs) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_hasPage)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: cs.surface,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.Globe,
                      size: 48,
                      color: cs.onSurface.withValues(alpha: 0.28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      zh ? '输入网址，从这扇窗望出去' : 'Type a URL to look outside',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
