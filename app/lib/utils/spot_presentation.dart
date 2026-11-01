import '../services/wind_api_service.dart';

const Map<String, double> kDirectionBearings = {
  'N': 0,
  'NNE': 22.5,
  'NE': 45,
  'ENE': 67.5,
  'E': 90,
  'ESE': 112.5,
  'SE': 135,
  'SSE': 157.5,
  'S': 180,
  'SSW': 202.5,
  'SW': 225,
  'WSW': 247.5,
  'W': 270,
  'WNW': 292.5,
  'NW': 315,
  'NNW': 337.5,
};

const List<String> kCompassSectors = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// Same 60-minute rule as [WindMeasurement.isFreshAt]. Uses the measurement
/// time when the payload has one, so a stale observation is not shown as live
/// just because the agent stored it moments ago.
bool readingIsFresh(WindMeasurement measurement, DateTime now) {
  return measurement.isFreshAt(now);
}

DateTime? measurementTime(WindMeasurement measurement) {
  for (final raw in [measurement.updatedAt, measurement.fetchedAt, measurement.observedAt]) {
    final parsed = _parse(raw);
    if (parsed != null) return parsed;
  }
  return null;
}

DateTime? _parse(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

double? bearingOf(String raw) {
  for (final token in _tokens(raw)) {
    final bearing = kDirectionBearings[token];
    if (bearing != null) return bearing;
  }
  return null;
}

Set<String> sectorsOf(String raw) {
  return _tokens(raw).where(kCompassSectors.contains).toSet();
}

Iterable<String> _tokens(String raw) {
  return raw.toUpperCase().split(RegExp(r'[^A-Z]+')).where((token) => token.isNotEmpty);
}

String displayWindow(String raw) => raw.replaceAll(' - ', '–');

String nextCheckLabel(String activeWindow, DateTime now) {
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(activeWindow);
  if (match == null) return activeWindow;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final start = DateTime(now.year, now.month, now.day, hour, minute);
  final dayWord = now.isAfter(start) ? 'morgen' : 'heute';
  final hh = hour.toString().padLeft(2, '0');
  final mm = minute.toString().padLeft(2, '0');
  return '$dayWord $hh:$mm';
}

String clockLabel(DateTime time) {
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String agoLabel(DateTime time, DateTime now) {
  var delta = now.difference(time);
  if (delta.isNegative) delta = Duration.zero;
  if (delta.inMinutes < 1) return 'gerade eben';
  if (delta.inMinutes < 60) return 'vor ${delta.inMinutes} Min';
  if (delta.inHours < 24) return 'vor ${delta.inHours} Std.';
  return 'vor ${delta.inDays} Tg.';
}

String compactHourWindow(String raw) {
  final match = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*[-–]\s*(\d{1,2})(?::(\d{2}))?').firstMatch(raw);
  if (match == null) return raw;
  String hour(String value, String? minute) {
    final hh = value.padLeft(2, '0');
    if (minute == null || minute == '00') return hh;
    return '$hh:$minute';
  }

  return '${hour(match.group(1)!, match.group(2))}–${hour(match.group(3)!, match.group(4))} Uhr';
}

String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Guten Morgen';
  if (now.hour < 18) return 'Guten Tag';
  return 'Guten Abend';
}

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

String homeDateLabel(DateTime now) {
  final weekday = _weekdays[now.weekday - 1];
  final month = _months[now.month - 1];
  return '$weekday, ${now.day}. $month · ${clockLabel(now)}'.toUpperCase();
}

String dayLabel(DateTime time) {
  final weekday = _weekdays[time.weekday - 1];
  final month = _months[time.month - 1];
  return '$weekday., ${time.day}. $month';
}

String tomorrowCaption(DateTime now) {
  final tomorrow = now.add(const Duration(days: 1));
  return 'für morgen (${_weekdays[tomorrow.weekday - 1]}.)';
}

class HourBin {
  final DateTime hour;
  final double knots;
  final bool forecast;

  const HourBin({required this.hour, required this.knots, this.forecast = false});
}

/// Today's observed hours. Hours without a sample are omitted.
List<HourBin> hourlyBinsToday(List<WindHistoryItem> history, DateTime now) {
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  final latest = <DateTime, WindHistoryItem>{};
  for (final item in history) {
    final time = item.observedAt.toLocal();
    if (time.isBefore(start) || !time.isBefore(end)) continue;
    final hour = DateTime(time.year, time.month, time.day, time.hour);
    final previous = latest[hour];
    if (previous == null || time.isAfter(previous.observedAt.toLocal())) {
      latest[hour] = item;
    }
  }
  final bins = latest.entries
      .map(
        (entry) => HourBin(
          hour: entry.key,
          knots: entry.value.baseWind,
          forecast: entry.key.isAfter(now),
        ),
      )
      .toList()
    ..sort((a, b) => a.hour.compareTo(b.hour));
  return bins;
}

List<WindHistoryItem> seriesLast12Hours(
  List<WindHistoryItem> history,
  DateTime now, {
  WindMeasurement? live,
}) {
  final from = now.subtract(const Duration(hours: 12));
  final items = history.where((item) {
    final time = item.observedAt.toLocal();
    return !time.isBefore(from) && !time.isAfter(now.add(const Duration(minutes: 1)));
  }).toList();
  if (live != null && readingIsFresh(live, now)) {
    final covered = items.any((item) => now.difference(item.observedAt.toLocal()).inMinutes.abs() < 2);
    if (!covered) {
      items.add(WindHistoryItem(observedAt: now, baseWind: live.baseWind, gust: live.gust));
    }
  }
  items.sort((a, b) => a.observedAt.compareTo(b.observedAt));
  return items;
}
