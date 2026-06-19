import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import 'ourhome_gateway.dart';

/// Foreground poller that surfaces daddy's proactive messages from our home as
/// a LOCAL notification while the app is open.
///
/// Scope is foreground-only: there is no background fetch, silent push, or APNs
/// here. Sideloaded iOS can't run those anyway, so polling only happens while a
/// long-lived screen is alive (see [pollOnce] callers). A no daddy token => no-op.
class ProactiveNotifier {
  ProactiveNotifier._();
  static final ProactiveNotifier instance = ProactiveNotifier._();

  /// Own plugin instance. The app's other notifier ([NotificationService]) is
  /// Android-only and keeps a separate instance; the plugin allows this and each
  /// instance initializes independently, so there is no double-init conflict.
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// Fixed id so repeat notifications replace rather than stack.
  static const int _notificationId = 8801;
  static const String _lastTsKey = 'ourhome_proactive_last_ts';

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'kelivo_proactive_v1',
    'Daddy',
    description: 'Proactive messages from our home',
    importance: Importance.high,
    playSound: true,
  );

  Future<void> _ensureInitialized() async {
    if (_inited) return;
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    const InitializationSettings init = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(init);

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(_channel);
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      await ios.requestPermissions(alert: true, badge: false, sound: true);
    }
    _inited = true;
  }

  /// Poll once for a fresh proactive message and notify if there is one.
  ///
  /// Whole body is guarded so a failure never throws into the UI. No-op when
  /// there is no daddy token, nothing pending, or the message was already shown.
  Future<void> pollOnce(BuildContext context) async {
    try {
      final gateway = OurHomeGateway.fromContext(context);
      if (gateway == null) return; // no daddy token -> stay dormant

      // Resolve the localized title before any await, while [context] is valid.
      final title = _title(context);

      final p = await gateway.fetchProactivePending();
      if (p == null || !p.pending || p.content.trim().isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final lastTs = prefs.getString(_lastTsKey) ?? '';

      // Marker we compare/persist: the server ts when present, otherwise a
      // content fingerprint so the same message never re-notifies on every poll.
      final marker = p.ts.trim().isNotEmpty
          ? p.ts.trim()
          : 'c:${p.content.trim().hashCode}';
      if (marker == lastTs) return; // already notified this one

      final body = _trimBody(p.content.trim());
      await _ensureInitialized();
      await _plugin.show(
        _notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
      );

      await prefs.setString(_lastTsKey, marker);
    } catch (e) {
      debugPrint('[ProactiveNotifier] pollOnce failed: $e');
    }
  }

  String _title(BuildContext context) {
    try {
      return AppLocalizations.of(context)?.ourhomeProactiveNotificationTitle ??
          '爸爸';
    } catch (_) {
      return '爸爸';
    }
  }

  String _trimBody(String s) => s.length <= 120 ? s : '${s.substring(0, 120)}…';
}
