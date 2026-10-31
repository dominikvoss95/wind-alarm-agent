import 'package:app/services/wind_api_service.dart';
import 'package:app/theme/wind_scale.dart';
import 'package:app/utils/alarm_history.dart';
import 'package:app/utils/spot_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wind scale boundaries and number color', () {
    expect(WindScale.band(7.9), WindBand.tooLittle);
    expect(WindScale.band(8), WindBand.light);
    expect(WindScale.band(11.9), WindBand.light);
    expect(WindScale.band(12), WindBand.rideable);
    expect(WindScale.band(17.9), WindBand.rideable);
    expect(WindScale.band(18), WindBand.good);
    expect(WindScale.band(24.9), WindBand.good);
    expect(WindScale.band(25), WindBand.strong);
    expect(WindScale.band(30), WindBand.strong);
    expect(WindScale.band(30.1), WindBand.veryStrong);

    expect(WindScale.verdict(14), 'fahrbar');
    expect(WindScale.todayVerdict(18), 'Heute gut');
    expect(WindScale.numberColor(4), WindScale.numberColor(0));
    expect(WindScale.numberColor(4) != WindScale.barColor(4), isTrue);
    expect(WindScale.numberColor(14), WindScale.barColor(14));
    expect(WindScale.isRideable(11), isFalse);
    expect(WindScale.isRideable(12), isTrue);
  });

  test('freshness follows the 60 minute updatedAt rule', () {
    final now = DateTime.now();
    final fresh = _measurement(now.subtract(const Duration(minutes: 3)));
    final stale = _measurement(now.subtract(const Duration(minutes: 90)));
    expect(readingIsFresh(fresh, now), fresh.isCurrentlyFresh);
    expect(readingIsFresh(stale, now), isFalse);
    expect(stale.isCurrentlyFresh, isFalse);
  });

  test('next window and direction bearings stay on the existing abbreviations', () {
    final afternoon = DateTime(2026, 10, 31, 16, 48);
    expect(nextCheckLabel('05:00 - 07:00', afternoon), 'morgen 05:00');
    expect(nextCheckLabel('05:00 - 07:00', DateTime(2026, 10, 31, 4, 10)), 'heute 05:00');
    expect(displayWindow('05:00 - 07:00'), '05:00–07:00');
    expect(bearingOf('SW'), 225);
    expect(bearingOf('N'), 0);
    expect(sectorsOf('SW, S, SE'), {'SW', 'S', 'SE'});
    expect(compactHourWindow('14:00 - 18:00'), '14–18 Uhr');
    expect(greetingFor(afternoon), 'Guten Tag');
  });

  test('hourly bins omit missing hours and do not invent forecast bars', () {
    final now = DateTime(2026, 10, 31, 16, 48);
    final history = [
      _history(DateTime(2026, 10, 31, 8, 10), 6),
      _history(DateTime(2026, 10, 31, 8, 40), 9),
      _history(DateTime(2026, 10, 31, 15, 5), 14),
      _history(DateTime(2026, 10, 30, 18, 0), 20),
    ];
    final bins = hourlyBinsToday(history, now);
    expect(bins.map((bin) => bin.hour.hour), [8, 15]);
    expect(bins.first.knots, 9);
    expect(bins.every((bin) => bin.forecast == false), isTrue);
  });

  test('alarms are the first reading of a day above the spot minimum', () {
    final now = DateTime(2026, 10, 31, 16, 48);
    final rows = alarmsFromHistory(
      now: now,
      historyByLocation: {
        'kochelsee': [
          _history(DateTime(2026, 10, 31, 5, 10), 8),
          _history(DateTime(2026, 10, 31, 5, 40), 15, gust: 19),
          _history(DateTime(2026, 10, 31, 6, 5), 16),
        ],
        'gardasee': [
          _history(DateTime(2026, 10, 31, 6, 41), 11),
          _history(DateTime(2026, 10, 26, 5, 48), 27, gust: 31),
        ],
      },
    );
    expect(rows, hasLength(2));
    expect(rows.first.locationName, 'Kochelsee');
    expect(rows.first.at.hour, 5);
    expect(rows.first.knots, 15);
    expect(rows.first.direction, 'SW');
    expect(rows.last.locationName, 'Gardasee');
    expect(rows.last.direction, 'N');
    expect(alarmBucket(rows.first.at, now), AlarmBucket.thisWeek);
  });
}

WindMeasurement _measurement(DateTime updated) {
  return WindMeasurement(
    location: 'kochelsee',
    baseWind: 14,
    gust: 19,
    fetchStatus: 'success',
    isFresh: true,
    thresholdExceeded: true,
    errorMessage: '',
    updatedAt: updated.toIso8601String(),
  );
}

WindHistoryItem _history(DateTime at, double knots, {double gust = 0}) {
  return WindHistoryItem(observedAt: at, baseWind: knots, gust: gust);
}
