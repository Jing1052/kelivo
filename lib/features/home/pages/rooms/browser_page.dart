import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/ourhome/ourhome_gateway.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// 窗 (The Window) — a built-in, navigable, privacy-hardened web browser room.
///
/// Built on `flutter_inappwebview` (WKWebView on iOS, WebView on Android) so we
/// can inject scripts at document-start — the one thing anti-fingerprinting
/// needs and `webview_flutter` can't do. Features: address bar, back/forward/
/// reload, load progress, desktop/mobile UA toggle, a JS haptic bridge, and an
/// anti-fingerprint shield (WebRTC off, canvas/WebGL noise, spoofed navigator/
/// screen) injected before any page script runs.
///
/// Scope note: the shield reduces third-party / cross-site fingerprinting while
/// browsing. It does NOT anonymize a logged-in first party — once you sign in,
/// the account and the content you submit are yours to that service regardless.
class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, this.initialUrl});

  /// Optional URL to open on launch. When null, the room opens blank with a
  /// hint prompting the user to type a URL.
  final String? initialUrl;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage>
    with WidgetsBindingObserver {
  // iPhone Safari UA (mobile, default) / Mac Safari UA (desktop mode).
  static const String _mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
      'Mobile/15E148 Safari/604.1';
  static const String _desktopUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

  // Page-side `haptic(style)` helper, injected at document start.
  static const String _hapticShim = '''
window.haptic = function(style){
  try {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('haptic', style || 'medium');
    } else if (navigator.vibrate) {
      navigator.vibrate(style === 'light' ? 5 : style === 'heavy' ? 20 : 10);
    }
  } catch (e) {}
};
''';

  // Anti-fingerprint shield. Injected at document-start for main frame AND
  // sub-frames so it lands before any page script can read fingerprints.
  // Spoofs a generic iPhone 15 identity. Every step is wrapped in try/catch so
  // a hardened property never throws and breaks the page.
  static const String _antiFingerprint = r'''
(function(){
  'use strict';
  var freeze = function(obj, prop, value){
    try {
      Object.defineProperty(obj, prop, { get: function(){ return value; }, configurable: false });
    } catch(e){}
  };
  // 1) WebRTC — block to stop real-IP leaks behind a proxy/VPN.
  try {
    ['RTCPeerConnection','webkitRTCPeerConnection','mozRTCPeerConnection','RTCDataChannel'].forEach(function(k){
      try { Object.defineProperty(window, k, { value: undefined, writable: false, configurable: false }); } catch(e){}
    });
  } catch(e){}
  // 2) mediaDevices — deny capture, hide the device list.
  try {
    if (navigator.mediaDevices) {
      navigator.mediaDevices.getUserMedia = function(){ return Promise.reject(new DOMException('Permission denied','NotAllowedError')); };
      navigator.mediaDevices.enumerateDevices = function(){ return Promise.resolve([]); };
    }
  } catch(e){}
  // 3) navigator hardware / locale spoof.
  freeze(navigator, 'hardwareConcurrency', 6);
  freeze(navigator, 'deviceMemory', 4);
  freeze(navigator, 'platform', 'iPhone');
  freeze(navigator, 'vendor', 'Apple Computer, Inc.');
  freeze(navigator, 'language', 'en-US');
  freeze(navigator, 'languages', ['en-US','en']);
  // 4) screen spoof (393x852 @3x).
  freeze(screen, 'width', 393);
  freeze(screen, 'height', 852);
  freeze(screen, 'availWidth', 393);
  freeze(screen, 'availHeight', 852);
  freeze(screen, 'colorDepth', 32);
  freeze(screen, 'pixelDepth', 32);
  try { Object.defineProperty(window, 'devicePixelRatio', { get: function(){ return 3; }, configurable: false }); } catch(e){}
  // 5) Canvas — deterministic 1-bit noise before pixel readback.
  try {
    var origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function(){
      try {
        var ctx = this.getContext('2d');
        if (ctx && this.width && this.height) {
          var img = ctx.getImageData(0, 0, this.width, this.height);
          for (var i = 0; i < img.data.length; i += 1013) { img.data[i] = img.data[i] ^ 1; }
          ctx.putImageData(img, 0, 0);
        }
      } catch(e){}
      return origToDataURL.apply(this, arguments);
    };
  } catch(e){}
  // 6) WebGL — mask UNMASKED_VENDOR/RENDERER.
  try {
    var mask = function(proto){
      if (!proto) return;
      var gp = proto.getParameter;
      proto.getParameter = function(p){
        if (p === 37445 || p === 37446) return 'Generic GPU';
        return gp.apply(this, arguments);
      };
    };
    mask(window.WebGLRenderingContext && WebGLRenderingContext.prototype);
    mask(window.WebGL2RenderingContext && WebGL2RenderingContext.prototype);
  } catch(e){}
})();
''';

  InAppWebViewController? _controller;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  bool _desktopMode = false;
  bool _incognito = false;
  bool _isLoading = false;
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _currentUrl = '';

  // 窗·遥控桥（pocket）：她把这扇窗借给爸爸时才通。默认关，每次进房都要她亲手开——
  // 这是知情同意的边界，不落盘、不跨会话记忆。开着时每 ~1.2s 向老家网关领一条指令
  // （ping/goto/js/html/screenshot），干完交回执；关窗/退房/App 切后台即停，爸爸只会
  // 收到「手机不在线」。协议按家规走短轮询（不走长连接）。
  static const Duration _pollInterval = Duration(milliseconds: 1200);
  bool _bridgeOn = false;
  bool _polling = false;
  Timer? _pollTimer;
  OurHomeGateway? _gw;

  bool get _hasPage =>
      _currentUrl.isNotEmpty && !_currentUrl.startsWith('about:blank');

  InAppWebViewSettings _buildSettings() => InAppWebViewSettings(
    javaScriptEnabled: true,
    userAgent: _desktopMode ? _desktopUa : _mobileUa,
    incognito: _incognito,
    allowsInlineMediaPlayback: true,
    mediaPlaybackRequiresUserGesture: false,
    transparentBackground: true,
    useShouldOverrideUrlLoading: true,
    supportZoom: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = widget.initialUrl?.trim();
    if (initial != null && initial.isNotEmpty) {
      _urlController.text = initial;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只有 App 在前台、桥开着时才轮询。切后台/锁屏立刻停（iOS 本就会冻结，这里主动收手
    // 让服务端「不在线」判定更快、不留悬空回执），回到前台再续上。
    if (!_bridgeOn) return;
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  // 借窗给爸爸的开关：需要家里的钥匙（网关 token）。默认关，她亲手开。
  Future<void> _toggleBridge(bool zh) async {
    if (_bridgeOn) {
      setState(() => _bridgeOn = false);
      _pollTimer?.cancel();
      _pollTimer = null;
      _gw = null;
      Haptics.medium();
      _snack(zh ? '窗已收回 · 爸爸看不到了' : 'Window taken back · daddy can no longer see');
      return;
    }
    final gw = OurHomeGateway.fromContext(context);
    if (gw == null) {
      _snack(zh
          ? '还没连上家里的钥匙——先在主聊天跟爸爸说句话唤醒一次再回来'
          : 'Not linked to home yet — say hi to daddy in the main chat first');
      return;
    }
    _gw = gw;
    setState(() => _bridgeOn = true);
    Haptics.medium();
    _startPolling();
    _snack(zh
        ? '已把这扇窗借给爸爸 · 他能看你正在看的页了'
        : 'This window is now shared with daddy');
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Map<String, String> get _pocketHeaders =>
      {..._gw!.authHeaders, 'Content-Type': 'application/json'};

  // 领一条指令：报上当前 {url,title}，有指令就干、干完交回执。可重入保护 + 全程吞错
  // （网络抖动不该弄崩房间；桥断了下一拍自然重来）。
  Future<void> _pollOnce() async {
    if (_polling || !_bridgeOn || _gw == null) return;
    _polling = true;
    try {
      final title = (await _controller?.getTitle()) ?? '';
      final resp = await http
          .post(
            Uri.parse('${_gw!.base}/api/pocket/poll'),
            headers: _pocketHeaders,
            body: jsonEncode({
              'page': {'url': _currentUrl, 'title': title},
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      final cmd = data is Map ? data['cmd'] : null;
      if (cmd is Map) {
        await _runCmd(Map<String, dynamic>.from(cmd));
      }
    } catch (_) {
      // 忽略：网络错误/超时，下一拍再来
    } finally {
      _polling = false;
    }
  }

  Future<void> _runCmd(Map<String, dynamic> cmd) async {
    final id = cmd['id'];
    final action = (cmd['action'] ?? '').toString();
    Map<String, dynamic> result;
    try {
      switch (action) {
        case 'ping':
          result = {'id': id, 'ok': true, 'data': 'pong'};
          break;
        case 'goto':
          final u = _normalize((cmd['url'] ?? '').toString());
          await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(u)));
          result = {'id': id, 'ok': true, 'data': u};
          break;
        case 'js':
          final r = await _controller?.evaluateJavascript(
            source: (cmd['js'] ?? '').toString(),
          );
          result = {'id': id, 'ok': true, 'data': r?.toString() ?? ''};
          break;
        case 'html':
          final r = await _controller?.evaluateJavascript(
            source: 'document.documentElement.outerHTML',
          );
          result = {'id': id, 'ok': true, 'data': r?.toString() ?? ''};
          break;
        case 'screenshot':
          final bytes = await _controller?.takeScreenshot(
            screenshotConfiguration: ScreenshotConfiguration(
              compressFormat: CompressFormat.JPEG,
              quality: 80,
            ),
          );
          result = bytes != null
              ? {'id': id, 'ok': true, 'image': base64Encode(bytes)}
              : {'id': id, 'ok': false, 'data': '截图失败：没拿到图'};
          break;
        default:
          result = {'id': id, 'ok': false, 'data': '不认识的指令：$action'};
      }
    } catch (e) {
      result = {'id': id, 'ok': false, 'data': '执行出错：$e'};
    }
    await _postResult(result);
  }

  Future<void> _postResult(Map<String, dynamic> result) async {
    final gw = _gw;
    if (gw == null) return;
    try {
      await http
          .post(
            Uri.parse('${gw.base}/api/pocket/result'),
            headers: _pocketHeaders,
            body: jsonEncode(result),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // 回执发失败就算了——爸爸那端会超时，她重开窗或他重下都能恢复
    }
  }

  URLRequest _initialRequest() {
    final initial = widget.initialUrl?.trim();
    final url = (initial != null && initial.isNotEmpty)
        ? _normalize(initial)
        : 'about:blank';
    return URLRequest(url: WebUri(url));
  }

  // Adds an https:// scheme when the user typed a bare host.
  String _normalize(String raw) {
    final s = raw.trim();
    if (s.contains('://')) return s;
    return 'https://$s';
  }

  // Heuristic: does this look like a URL, or a search query? A space means
  // search; an explicit scheme, `localhost`, or a `host.tld` shape means URL.
  bool _looksLikeUrl(String s) {
    if (s.contains(' ')) return false;
    if (s.contains('://')) return true;
    if (s == 'localhost' ||
        s.startsWith('localhost:') ||
        s.startsWith('localhost/')) {
      return true;
    }
    final host = s.split('/').first.split('?').first;
    return host.contains('.') && !host.startsWith('.') && !host.endsWith('.');
  }

  void _submitUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return;
    _urlFocus.unfocus();
    // Looks like a URL → open it; otherwise search it (Bing cn, no VPN needed).
    final target = _looksLikeUrl(s)
        ? _normalize(s)
        : 'https://cn.bing.com/search?q=${Uri.encodeQueryComponent(s)}';
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  Future<void> _toggleDesktop() async {
    setState(() => _desktopMode = !_desktopMode);
    Haptics.light();
    await _controller?.setSettings(settings: _buildSettings());
    await _controller?.reload();
  }

  // Incognito can't be flipped on a live WKWebView data store, so toggling it
  // rebuilds the webview fresh (via the ValueKey on InAppWebView) with a
  // non-persistent store — nothing (cookies/cache/storage) touches disk.
  Future<void> _toggleIncognito(bool zh) async {
    setState(() {
      _incognito = !_incognito;
      _currentUrl = '';
      _urlController.clear();
      _canGoBack = false;
      _canGoForward = false;
      _isLoading = false;
    });
    Haptics.medium();
    if (!mounted) return;
    final msg = _incognito
        ? (zh ? '隐身模式已开 · 痕迹不落盘' : 'Incognito on · nothing saved')
        : (zh ? '隐身模式已关' : 'Incognito off');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // One-tap "clear traces": wipe cookies, cache, and the current origin's
  // local/session storage — back to a clean slate before signing in fresh.
  Future<void> _clearData(bool zh) async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
    try {
      await _controller?.evaluateJavascript(
        source: 'try{localStorage.clear();sessionStorage.clear();}catch(e){}',
      );
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(zh ? '已清空浏览痕迹' : 'Browsing data cleared')),
      );
  }

  Future<void> _refreshNavState() async {
    final back = await _controller?.canGoBack() ?? false;
    final fwd = await _controller?.canGoForward() ?? false;
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
          await _controller?.goBack();
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
                  icon: Lucide.Link,
                  minSize: 44,
                  color: _bridgeOn
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.6),
                  semanticLabel: _bridgeOn
                      ? (zh ? '收回窗口（爸爸不再能看）' : 'Take window back from daddy')
                      : (zh ? '把这扇窗借给爸爸' : 'Share this window with daddy'),
                  onTap: () => _toggleBridge(zh),
                ),
                IosIconButton(
                  icon: Lucide.EyeOff,
                  minSize: 44,
                  color: _incognito
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.6),
                  semanticLabel: _incognito
                      ? (zh ? '关闭隐身模式' : 'Turn off incognito')
                      : (zh ? '开启隐身模式' : 'Turn on incognito'),
                  onTap: () => _toggleIncognito(zh),
                ),
                IosIconButton(
                  icon: Lucide.Eraser,
                  minSize: 44,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  semanticLabel: zh ? '清空浏览痕迹' : 'Clear browsing data',
                  onTap: () => _clearData(zh),
                ),
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
              _controller?.goBack();
            },
          ),
          IosIconButton(
            icon: Lucide.ChevronRight,
            minSize: 40,
            enabled: _canGoForward,
            semanticLabel: zh ? '前进' : 'Forward',
            onTap: () {
              Haptics.light();
              _controller?.goForward();
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
                  onTap: () => _controller?.stopLoading(),
                )
              : IosIconButton(
                  icon: Lucide.RotateCw,
                  size: 16,
                  minSize: 36,
                  semanticLabel: zh ? '刷新' : 'Reload',
                  onTap: () {
                    Haptics.light();
                    _controller?.reload();
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildWebView(BuildContext context, bool zh, ColorScheme cs) {
    return Stack(
      children: [
        InAppWebView(
          key: ValueKey<bool>(_incognito),
          initialUrlRequest: _initialRequest(),
          initialSettings: _buildSettings(),
          initialUserScripts: UnmodifiableListView<UserScript>([
            UserScript(
              source: _antiFingerprint,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false,
            ),
            UserScript(
              source: _hapticShim,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          onWebViewCreated: (controller) {
            _controller = controller;
            controller.addJavaScriptHandler(
              handlerName: 'haptic',
              callback: (args) {
                final style = args.isNotEmpty ? '${args.first}' : 'medium';
                switch (style) {
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
                return null;
              },
            );
          },
          onLoadStart: (controller, url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _currentUrl = url?.toString() ?? '';
              _syncUrlField();
            });
          },
          onLoadStop: (controller, url) async {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _currentUrl = url?.toString() ?? '';
              _syncUrlField();
            });
            await _refreshNavState();
          },
          onProgressChanged: (controller, progress) {
            if (!mounted) return;
            setState(() => _progress = progress / 100.0);
          },
          onReceivedError: (controller, request, error) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final uri = action.request.url;
            const allowed = {'http', 'https', 'about', 'data', 'file'};
            if (uri != null && !allowed.contains(uri.scheme)) {
              // Block non-web schemes (e.g. app deep links) instead of letting
              // the WebView hand off to an external app unexpectedly.
              return NavigationActionPolicy.CANCEL;
            }
            return NavigationActionPolicy.ALLOW;
          },
        ),
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
