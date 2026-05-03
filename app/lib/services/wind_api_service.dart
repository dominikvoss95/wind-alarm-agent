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
  });

  factory WindMeasurement.fromJson(String location, Map<String, dynamic> json) {
    return WindMeasurement(
      location: location,
      baseWind: (json['base_wind'] ?? 0.0).toDouble(),
      gust: (json['gust'] ?? 0.0).toDouble(),
      observedAt: json['observed_at'],
      fetchedAt: json['fetched_at'],
      fetchStatus: json['fetch_status'] ?? 'unknown',
      isFresh: json['is_fresh'] ?? false,
      thresholdExceeded: json['threshold_exceeded'] ?? false,
      errorMessage: json['error_message'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }

  bool get isValid => fetchStatus == 'success' && updatedAt.isNotEmpty;
}

class WindApiService {
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-API-Key': _apiKey,
  };

  static Future<WindMeasurement?> getMeasurement(String location) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/measurements/$location'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return WindMeasurement.fromJson(location, json);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, WindMeasurement?>> getAllMeasurements() async {
    try {
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
}