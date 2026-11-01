import 'package:app/push/alarm_push.dart';
import 'package:app/utils/alarm_utils.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('armed locations subscribe to their own topics', () {
    expect(
      topicsForArmed(
        const [true, false],
        const ['wind_alarms_kochelsee', 'wind_alarms_gardasee'],
      ),
      ['wind_alarms_kochelsee'],
    );
    expect(
      topicsForArmed(
        const [true, true],
        const ['wind_alarms_kochelsee', 'wind_alarms_gardasee'],
      ),
      ['wind_alarms_kochelsee', 'wind_alarms_gardasee'],
    );
    expect(topicsForArmed(const [false, false], const ['wind_alarms_kochelsee']), isEmpty);
  });

  test('local alarm is not raised twice when iOS already shows the push', () {
    const data = {'action': 'schedule_alarm', 'location': 'gardasee', 'wind': '13.2'};
    expect(isScheduleAlarm(data), isTrue);
    expect(shouldPresentLocalAlarm(data: data, systemWillPresent: true), isFalse);
    expect(shouldPresentLocalAlarm(data: data, systemWillPresent: false), isTrue);
    expect(
      shouldPresentLocalAlarm(data: const {'wind': '20'}, systemWillPresent: false),
      isFalse,
    );
    expect(alarmLocationName(data), 'GARDASEE');
    expect(alarmLocationName(const {}), 'KOCHELSEE');
  });

  test('iOS local alarm uses the bundled sound and time-sensitive level', () {
    final details = iosAlarmDetails();
    expect(details.sound, alarmSoundFile);
    expect(details.sound, 'alarm_sound.mp3');
    expect(details.interruptionLevel, InterruptionLevel.timeSensitive);
    expect(details.presentAlert, isTrue);
    expect(details.presentSound, isTrue);
  });
}