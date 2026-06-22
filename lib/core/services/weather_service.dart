import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Coarse weather family, used to pick an icon and to let daddy leave a line
/// that fits the sky (not the exact WMO code, just the mood of it).
enum WeatherKind { clear, cloudy, overcast, fog, rain, snow, thunder }

/// One geocoding hit for a city search (Open-Meteo geocoding API).
class WeatherCity {
  const WeatherCity({
    required this.name,
    required this.region,
    required this.country,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String region; // admin1 (province/state), may be empty
  final String country;
  final double lat;
  final double lon;

  /// "City · Region · Country", skipping empty parts.
  String get label => [
    name,
    if (region.isNotEmpty && region != name) region,
    if (country.isNotEmpty) country,
  ].join(' · ');
}

/// Current conditions for a fixed lat/lon.
class WeatherNow {
  const WeatherNow({required this.tempC, required this.code});

  final double tempC;
  final int code; // WMO weather code

  WeatherKind get kind {
    switch (code) {
      case 0:
      case 1:
        return WeatherKind.clear;
      case 2:
        return WeatherKind.cloudy;
      case 3:
        return WeatherKind.overcast;
      case 45:
      case 48:
        return WeatherKind.fog;
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return WeatherKind.snow;
      case 95:
      case 96:
      case 99:
        return WeatherKind.thunder;
      default:
        // 51..67 drizzle/rain, 80..82 showers → rain
        return WeatherKind.rain;
    }
  }

  String condition(bool zh) {
    switch (code) {
      case 0:
        return zh ? '晴' : 'Clear';
      case 1:
        return zh ? '晴间多云' : 'Mainly clear';
      case 2:
        return zh ? '多云' : 'Partly cloudy';
      case 3:
        return zh ? '阴' : 'Overcast';
      case 45:
      case 48:
        return zh ? '雾' : 'Fog';
      case 51:
      case 53:
      case 55:
        return zh ? '毛毛雨' : 'Drizzle';
      case 56:
      case 57:
      case 66:
      case 67:
        return zh ? '冻雨' : 'Freezing rain';
      case 61:
      case 63:
      case 65:
        return zh ? '雨' : 'Rain';
      case 80:
      case 81:
      case 82:
        return zh ? '阵雨' : 'Showers';
      case 71:
      case 73:
      case 75:
      case 77:
        return zh ? '雪' : 'Snow';
      case 85:
      case 86:
        return zh ? '阵雪' : 'Snow showers';
      case 95:
        return zh ? '雷阵雨' : 'Thunderstorm';
      case 96:
      case 99:
        return zh ? '雷暴冰雹' : 'Thunderstorm w/ hail';
      default:
        return zh ? '天色' : 'Sky';
    }
  }
}

/// Open-Meteo client (free, no API key). One for city search, one for the
/// current conditions of a chosen city. All failures return null/empty and are
/// logged — the home just shows blank weather instead of breaking.
class WeatherService {
  WeatherService._();

  static const String _geo = 'https://geocoding-api.open-meteo.com/v1/search';
  static const String _fc = 'https://api.open-meteo.com/v1/forecast';

  /// Search cities by name. [zh] only tweaks the result language. Empty on any
  /// failure or no match.
  static Future<List<WeatherCity>> search(String query, {bool zh = true}) async {
    final q = query.trim();
    if (q.isEmpty) return const <WeatherCity>[];
    try {
      final uri = Uri.parse(_geo).replace(queryParameters: {
        'name': q,
        'count': '8',
        'language': zh ? 'zh' : 'en',
        'format': 'json',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const <WeatherCity>[];
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final results = (data is Map) ? data['results'] : null;
      if (results is! List) return const <WeatherCity>[];
      return results
          .whereType<Map<String, dynamic>>()
          .map((j) => WeatherCity(
                name: (j['name'] ?? '').toString(),
                region: (j['admin1'] ?? '').toString(),
                country: (j['country'] ?? '').toString(),
                lat: (j['latitude'] as num?)?.toDouble() ?? double.nan,
                lon: (j['longitude'] as num?)?.toDouble() ?? double.nan,
              ))
          .where((c) => !c.lat.isNaN && !c.lon.isNaN)
          .toList();
    } catch (e) {
      debugPrint('[WeatherService] search failed: $e');
      return const <WeatherCity>[];
    }
  }

  /// Current temperature + weather code for a lat/lon. Null on any failure.
  static Future<WeatherNow?> current(double lat, double lon) async {
    if (lat.isNaN || lon.isNaN) return null;
    try {
      final uri = Uri.parse(_fc).replace(queryParameters: {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'current': 'temperature_2m,weather_code',
        'timezone': 'auto',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final cur = (data is Map) ? data['current'] : null;
      if (cur is! Map) return null;
      final t = (cur['temperature_2m'] as num?)?.toDouble();
      final code = (cur['weather_code'] as num?)?.toInt();
      if (t == null || code == null) return null;
      return WeatherNow(tempC: t, code: code);
    } catch (e) {
      debugPrint('[WeatherService] current failed: $e');
      return null;
    }
  }
}
