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
    return WindMeasurement(
      location: location,
      baseWind: (json['base_wind'] ?? (json['base_wind_knots'] ?? 0.0)).toDouble(),
      gust: (json['gust'] ?? (json['gust_knots'] ?? 0.0)).toDouble(),
      observedAt: json['observed_at'],
      fetchedAt: json['fetched_at'],
      fetchStatus: json['fetch_status'] ?? 'unknown',
      isFresh: json['is_fresh'] ?? false,
      thresholdExceeded: json['threshold_exceeded'] ?? false,
      errorMessage: json['error_message'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      webcams: json['webcams'] as Map<String, dynamic>?,
    );
  }

  bool get isValid => fetchStatus == 'success' && updatedAt.isNotEmpty;

  bool get isCurrentlyFresh {
    if (updatedAt.isEmpty) return false;
    try {
      final updatedTime = DateTime.parse(updatedAt).toLocal();
      final difference = DateTime.now().difference(updatedTime);
      return difference.inMinutes < 60;
    } catch (_) {
      return false;
    }
  }
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
          return jsonList.map((item) => WindHistoryItem.fromJson(item)).toList();
        }
        return [];
      } else {
        final response = await http.get(
          Uri.parse('$_baseUrl/measurements/$location/history?hours=$hours'),
          headers: _headers,
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List<dynamic> jsonList = jsonDecode(response.body);
          return jsonList.map((item) => WindHistoryItem.fromJson(item)).toList();
        }
        return [];
      }
    } catch (e) {
      return [];
    }
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
        return null;
      }
      return null;
    } catch (e) {
      return null;
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
      observedAt: DateTime.parse(json['observed_at']).toLocal(),
      baseWind: (json['base_wind'] ?? 0.0).toDouble(),
      gust: (json['gust'] ?? 0.0).toDouble(),
    );
  }
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