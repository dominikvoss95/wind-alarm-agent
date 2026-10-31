import '../models/location.dart';
import '../services/wind_api_service.dart';

class AlarmEntry {
  final String locationId;
  final String locationName;
  final String direction;
  final DateTime at;
  final double knots;
  final double gust;

  const AlarmEntry({
    required this.locationId,
    required this.locationName,
    required this.direction,
    required this.at,
    required this.knots,
    required this.gust,
  });
}

enum AlarmBucket { thisWeek, lastWeek, older }

/// One row per spot and day: the first reading at or above that spot's minimum.
List<AlarmEntry> alarmsFromHistory({
  required Map<String, List<WindHistoryItem>> historyByLocation,
  required DateTime now,
}) {
  final cutoff = now.subtract(const Duration(days: 30));
  final earliest = <String, AlarmEntry>{};
  for (final location in WindLocation.values) {
    final data = appLocations[location]!;
    final history = historyByLocation[location.name] ?? const <WindHistoryItem>[];
    for (final item in history) {
      final at = item.observedAt.toLocal();
      if (at.isBefore(cutoff) || at.isAfter(now.add(const Duration(minutes: 1)))) continue;
      if (item.baseWind < data.alarmThresholdKnots) continue;
      final key = '${data.id}-${at.year}-${at.month}-${at.day}';
      final current = earliest[key];
      if (current == null || at.isBefore(current.at)) {
        earliest[key] = AlarmEntry(
          locationId: data.id,
          locationName: data.name,
          direction: data.defaultDirection,
          at: at,
          knots: item.baseWind,
          gust: item.gust,
        );
      }
    }
  }
  final rows = earliest.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  return rows;
}

AlarmBucket alarmBucket(DateTime at, DateTime now) {
  final start = _monday(now);
  final previous = start.subtract(const Duration(days: 7));
  final day = DateTime(at.year, at.month, at.day);
  if (!day.isBefore(start)) return AlarmBucket.thisWeek;
  if (!day.isBefore(previous)) return AlarmBucket.lastWeek;
  return AlarmBucket.older;
}

String alarmBucketLabel(AlarmBucket bucket) {
  switch (bucket) {
    case AlarmBucket.thisWeek:
      return 'Diese Woche';
    case AlarmBucket.lastWeek:
      return 'Letzte Woche';
    case AlarmBucket.older:
      return 'Älter';
  }
}

DateTime _monday(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

String monitoredCaption() {
  final names = WindLocation.values.map((location) => appLocations[location]!.name).join(', ');
  final thresholds = WindLocation.values
      .map((location) => appLocations[location]!.alarmThresholdKnots.round())
      .toSet()
      .toList()
    ..sort();
  final thresholdText = thresholds.length == 1
      ? 'ab ${thresholds.first} kts'
      : 'ab ${thresholds.first}–${thresholds.last} kts';
  return 'Überwacht: $names · $thresholdText';
}
