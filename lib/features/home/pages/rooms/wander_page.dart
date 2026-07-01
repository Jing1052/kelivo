import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/shared/widgets/chat_backdrop.dart';

import '../../../../theme/app_font_weights.dart';
import '../../../../icons/lucide_adapter.dart';
import '../../../../core/services/haptics.dart';
import '../../../../shared/widgets/ios_tactile.dart';

/// 漫游 (Wander) — a Google Street View wandering room. Hosts the self-contained
/// `assets/html/wander.html` tool inside a WebView. Street View needs a Google
/// Maps API key; the key is never baked into the repo — it's stored on-device
/// (SharedPreferences) and injected into the page at load time. Without a key,
/// map / search / random roam / GeoGuessr still work; only Street View shows a
/// placeholder hint.
class WanderPage extends StatefulWidget {
  const WanderPage({super.key});

  @override
  State<WanderPage> createState() => _WanderPageState();
}

class _WanderPageState extends State<WanderPage> {
  /// On-device key store. Not a secret shipped in the repo — the user pastes
  /// their own key once and it stays on their phone.
  static const String _apiKeyPref = 'wander_gmaps_api_key';

  /// Gives the loaded HTML a real origin so the page's localStorage (历史足迹)
  /// persists across opens instead of living on the null about:blank origin.
  static const String _baseUrl = 'https://wander.stillhere.local/';

  WebViewController? _controller;
  bool _loading = true;
  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyPref) ?? '';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFDF9F1))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      );
    if (!mounted) return;
    setState(() => _controller = controller);
    await _loadContent(controller);
  }

  Future<void> _loadContent(WebViewController controller) async {
    if (mounted) setState(() => _loading = true);
    var html = await rootBundle.loadString('assets/html/wander.html');
    if (_apiKey.isNotEmpty) {
      // wander.html declares `var GOOGLE_API_KEY = '';` — inject the stored key.
      html = html.replaceFirst(
        "var GOOGLE_API_KEY = ''",
        "var GOOGLE_API_KEY = '$_apiKey'",
      );
    }
    await controller.loadHtmlString(html, baseUrl: _baseUrl);
  }

  Future<void> _editApiKey() async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: _apiKey);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            18 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Lucide.KeyRound, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Google Maps API Key',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                zh
                    ? '街景需要它。没有也能用地图、搜索、随机漫游和猜位置游戏。'
                    : 'Street View needs it. Map, search, random roam and the guessing game work without it.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 15, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'AIza…',
                  filled: true,
                  fillColor: cs.onSurface.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              IosCardPress(
                borderRadius: BorderRadius.circular(12),
                baseColor: cs.onSurface.withValues(alpha: 0.05),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: () async {
                  final uri = Uri.parse(
                    'https://developers.google.com/maps/documentation/javascript/get-api-key',
                  );
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: Row(
                  children: [
                    Icon(Lucide.Globe, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        zh ? '怎么申请 Key？' : 'How to get a key?',
                        style: TextStyle(fontSize: 13.5, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: IosCardPress(
                      borderRadius: BorderRadius.circular(12),
                      baseColor: cs.onSurface.withValues(alpha: 0.06),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      onTap: () => Navigator.of(ctx).pop('__cancel__'),
                      child: Center(
                        child: Text(
                          zh ? '取消' : 'Cancel',
                          style: TextStyle(
                            fontSize: 15,
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IosCardPress(
                      borderRadius: BorderRadius.circular(12),
                      baseColor: cs.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      onTap: () => Navigator.of(ctx).pop(controller.text.trim()),
                      child: Center(
                        child: Text(
                          zh ? '保存' : 'Save',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: AppFontWeights.semibold,
                            color: cs.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();
    if (result == null || result == '__cancel__') return;
    if (result == _apiKey) return;
    _apiKey = result;
    final prefs = await SharedPreferences.getInstance();
    if (result.isEmpty) {
      await prefs.remove(_apiKeyPref);
    } else {
      await prefs.setString(_apiKeyPref, result);
    }
    final controller = _controller;
    if (controller != null) await _loadContent(controller);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final controller = _controller;

    return Stack(
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
              zh ? '漫游' : 'Wander',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            actions: [
              IosIconButton(
                icon: Lucide.KeyRound,
                size: 20,
                minSize: 44,
                onTap: () {
                  Haptics.soft();
                  _editApiKey();
                },
              ),
              IosIconButton(
                icon: Lucide.RefreshCw,
                size: 20,
                minSize: 44,
                onTap: () {
                  final c = _controller;
                  if (c != null) {
                    Haptics.soft();
                    _loadContent(c);
                  }
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: controller == null
              ? const SizedBox.shrink()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    WebViewWidget(controller: controller),
                    if (_loading)
                      const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
