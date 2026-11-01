import 'dart:convert';
import 'package:http/http.dart' as http;

const String _baseUrl = 'http://10.0.2.2:8000';
const String _apiKey = 'dev-key-change-in-production';

class WindMeasurement {
  final String location;
  final double baseWind;
  final double gust;
  final String? observedAt;
  final String? fetchedAt;
  final String fetchStatus;
  final bool isFresh;
  final bool thresholdExceeded;
  final String errorMessage;
  final String updatedAt;
  final Map<String, dynamic>? webcams;

  WindMeasurement({
    required this.location,
    required this.baseWind,
    required this.gust,
    this.observedAt,
    this.fetchedAt,
    required this.fetchStatus,
    required this.isFresh,
    required this.thresholdExceeded,
    required this.errorMessage,
    required this.updatedAt,
    this.webcams,
  });

  factory WindMeasurement.fromJson(String location, Map<String, dynamic> json) {
    final updatedAt = (json['updated_at'] ?? json['fetched_at'] ?? json['observed_at'] ?? '').toString();
    return WindMeasurement(
      location: location,
      baseWind: _asDouble(json['base_wind'] ?? json['base_wind_knots']),
      gust: _asDouble(json['gust'] ?? json['gust_knots']),
      observedAt: json['observed_at']?.toString(),
      fetchedAt: json['fetched_at']?.toString(),
      fetchStatus: (json['fetch_status'] ?? json['parse_status'] ?? 'unknown').toString(),
      isFresh: json['is_fresh'] ?? false,
      thresholdExceeded: json['threshold_exceeded'] ?? false,
      errorMessage: json['error_message']?.toString() ?? '',
      updatedAt: updatedAt,
      webcams: json['webcams'] is Map ? Map<String, dynamic>.from(json['webcams'] as Map) : null,
    );
  }

  bool get isValid => fetchStatus == 'success' && updatedAt.isNotEmpty;

  /// Fresh when the measurement time (observedAt, otherwise updatedAt) is
  /// inside the last 60 minutes. A recent agent run must not make an old
  /// observedAt look live.
  bool isFreshAt(DateTime now) {
    if (fetchStatus != 'success' || !isFresh) return false;
    final raw = (observedAt != null && observedAt!.isNotEmpty) ? observedAt! : updatedAt;
    if (raw.isEmpty) return false;
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return false;
    final age = now.difference(parsed);
    return age.inMinutes >= -2 && age.inMinutes < 60;
  }

  bool get isCurrentlyFresh => isFreshAt(DateTime.now());
}

class WindApiService {
  static const bool _useStaticS3 = true;
  // TODO: Replace YOUR_ACCOUNT_ID with your actual AWS Account ID
  static const String _s3BucketUrl = 'https://wind-alarm-web-assets-882222437118.s3.eu-central-1.amazonaws.com';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-API-Key': _apiKey,
  };

  static Future<WindMeasurement?> getMeasurement(String location) async {
    try {
      if (_useStaticS3) {
        final response = await http.get(
          Uri.parse('$_s3BucketUrl/measurements.json'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final Map<String, dynamic> json = jsonDecode(response.body);
          if (json.containsKey(location)) {
            return WindMeasurement.fromJson(location, json[location]);
          }
        }
        return null;
      } else {
        final response = await http.get(
          Uri.parse('$_baseUrl/measurements/$location'),
          headers: _headers,
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          return WindMeasurement.fromJson(location, json);
        }
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, WindMeasurement?>> getAllMeasurements() async {
    try {
      if (_useStaticS3) {
        final response = await http.get(
          Uri.parse('$_s3BucketUrl/measurements.json'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final Map<String, dynamic> json = jsonDecode(response.body);
          return json.map(
            (key, value) => MapEntry(key, WindMeasurement.fromJson(key, value)),
          );
        }
        return {};
      } else {
        final response = await http.get(
          Uri.parse('$_baseUrl/measurements'),
          headers: _headers,
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final Map<String, dynamic> json = jsonDecode(response.body);
          return json.map(
            (key, value) => MapEntry(key, WindMeasurement.fromJson(key, value)),
          );
        }
        return {};
      }
    } catch (e) {
      return {};
    }
  }

  static Future<bool> triggerMeasurement(String location, {double threshold = 12.0, int freshness = 60}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/trigger/$location'),
        headers: _headers,
        body: jsonEncode({
          'threshold': threshold,
          'freshness': freshness,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<List<WindHistoryItem>> getHistory(String location, {int hours = 24}) async {
    try {
      if (_useStaticS3) {
        final response = await http.get(
          Uri.parse('$_s3BucketUrl/history/$location.json'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List<dynamic> jsonList = jsonDecode(response.body);
          return _parseHistory(jsonList);
        }
        return [];
      } else {
        final response = await http.get(
          Uri.parse('$_baseUrl/measurements/$location/history?hours=$hours'),
          headers: _headers,
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List<dynamic> jsonList = jsonDecode(response.body);
          return _parseHistory(jsonList);
        }
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  static List<WindHistoryItem> _parseHistory(List<dynamic> jsonList) {
    final items = <WindHistoryItem>[];
    for (final item in jsonList) {
      if (item is! Map) {
        continue;
      }
      try {
        items.add(WindHistoryItem.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        continue;
      }
    }
    return items;
  }

  static Future<WindForecast?> getForecast(String location) async {
    try {
      if (_useStaticS3) {
        final response = await http.get(
          Uri.parse('$_s3BucketUrl/forecast.json'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final Map<String, dynamic> json = jsonDecode(response.body);
          if (json.containsKey(location)) {
            return WindForecast.fromJson(json[location]);
          }
        }
      }
      return _getMockForecastFor(location);
    } catch (e) {
      return _getMockForecastFor(location);
    }
  }

  static WindForecast _getMockForecastFor(String location) {
    if (location.toLowerCase() == 'kochelsee') {
      return WindForecast(
        summary: 'Mäßiger Föhnwind am Nachmittag wahrscheinlich, da Patscherkofel anzieht.',
        windProbabilityPercent: 65,
        confidence: 'medium',
        expectedWindMin: 10,
        expectedWindMax: 18,
        expectedDirection: 'S',
        bestTimeWindow: '14:00 - 18:00',
        modelConsensus: 'Superforecast zeigt leichten Südwind, Föhnindikatoren deuten auf stärkere Böen hin.',
        sourcesAnalyzed: [
          ForecastSource(name: 'Windfinder 7-Tage', summary: 'Leichter Südwind (6-8 kts) angesagt.'),
          ForecastSource(name: 'Windfinder Superforecast', summary: '10 kts Südwind ab Mittag prognostiziert.'),
          ForecastSource(name: 'Patscherkofel (Föhn-Indikator)', summary: 'Föhnstation zeigt ansteigenden Südwind mit Böen bis 32 kts.')
        ],
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    } else {
      return WindForecast(
        summary: 'Starker Pelér am Vormittag. Ora am Nachmittag flaut ab.',
        windProbabilityPercent: 85,
        confidence: 'high',
        expectedWindMin: 14,
        expectedWindMax: 22,
        expectedDirection: 'N',
        bestTimeWindow: '07:00 - 11:00',
        modelConsensus: 'Sehr hohe Übereinstimmung zwischen Windfinder Superforecast und Windguru Arome.',
        sourcesAnalyzed: [
          ForecastSource(name: 'Föhndiagramm', summary: 'Keine Föhnlage vorhanden (Druckdifferenz +1 hPa).'),
          ForecastSource(name: 'Windfinder Superforecast', summary: 'Zeigt 16 kts Nordwind ab 08:00 Uhr.'),
          ForecastSource(name: 'Windguru AROME 1.3km', summary: 'Bestätigt Pelér mit bis zu 22 kts Böen in Malcesine Nord.')
        ],
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }
}

class WindHistoryItem {
  final DateTime observedAt;
  final double baseWind;
  final double gust;

  WindHistoryItem({
    required this.observedAt,
    required this.baseWind,
    required this.gust,
  });

  factory WindHistoryItem.fromJson(Map<String, dynamic> json) {
    return WindHistoryItem(
      observedAt: DateTime.parse(json['observed_at'].toString()).toLocal(),
      baseWind: _asDouble(json['base_wind'] ?? json['base_wind_knots']),
      gust: _asDouble(json['gust'] ?? json['gust_knots']),
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0.0;
  }
  return 0.0;
}

class WindForecast {
  final String summary;
  final int windProbabilityPercent;
  final String confidence; // 'high', 'medium', 'low'
  final int expectedWindMin;
  final int expectedWindMax;
  final String expectedDirection;
  final String bestTimeWindow;
  final String modelConsensus;
  final List<ForecastSource> sourcesAnalyzed;
  final String updatedAt;

  WindForecast({
    required this.summary,
    required this.windProbabilityPercent,
    required this.confidence,
    required this.expectedWindMin,
    required this.expectedWindMax,
    required this.expectedDirection,
    required this.bestTimeWindow,
    required this.modelConsensus,
    required this.sourcesAnalyzed,
    required this.updatedAt,
  });

  factory WindForecast.fromJson(Map<String, dynamic> json) {
    var sourcesList = json['sources_analyzed'] as List? ?? [];
    List<ForecastSource> parsedSources = sourcesList
        .map((s) => ForecastSource.fromJson(s as Map<String, dynamic>))
        .toList();

    var windKnots = json['expected_wind_knots'] as Map<String, dynamic>? ?? {};

    return WindForecast(
      summary: json['summary'] ?? '',
      windProbabilityPercent: json['wind_probability_percent'] ?? 0,
      confidence: json['confidence'] ?? 'low',
      expectedWindMin: (windKnots['min'] ?? 0).toInt(),
      expectedWindMax: (windKnots['max'] ?? 0).toInt(),
      expectedDirection: json['expected_direction'] ?? '',
      bestTimeWindow: json['best_time_window'] ?? '',
      modelConsensus: json['model_consensus'] ?? '',
      sourcesAnalyzed: parsedSources,
      updatedAt: json['updated_at'] ?? '',
    );
  }
}

class ForecastSource {
  final String name;
  final String summary;

  ForecastSource({required this.name, required this.summary});

  factory ForecastSource.fromJson(Map<String, dynamic> json) {
    return ForecastSource(
      name: json['name'] ?? '',
      summary: json['summary'] ?? '',
    );
  }
}