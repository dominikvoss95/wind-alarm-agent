import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/alarm_status.dart';
import '../utils/spot_presentation.dart';
import 'mira_controls.dart';

class SetupDashboard extends StatelessWidget {
  final AlarmChannelStatus status;
  final DateTime? lastTestAt;
  final DateTime now;
  final VoidCallback onTestKochelsee;
  final VoidCallback onTestGardasee;

  const SetupDashboard({
    super.key,
    required this.status,
    required this.now,
    required this.onTestKochelsee,
    required this.onTestGardasee,
    this.lastTestAt,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(MiraSpace.screen, MiraSpace.screen, MiraSpace.screen, miraBottomInset(context)),
      children: [
        Text('Setup & Test', style: mira.h1),
        const SizedBox(height: 28),
        const MiraLabel('Benachrichtigungen'),
        const SizedBox(height: MiraSpace.gap),
        MiraGroup(
          rows: [
            _StatusRow(
              icon: Icons.notifications_active_rounded,
              title: status.criticalTitle,
              subtitle: status.criticalSubtitle,
              trailing: status.showCriticalCheck
                  ? const Icon(Icons.check_circle_rounded, color: MiraColors.windGood, size: 26)
                  : null,
            ),
            _StatusRow(
              icon: Icons.music_note_rounded,
              title: 'Ton',
              subtitle: status.toneSubtitle,
            ),
            _StatusRow(
              icon: Icons.alarm_rounded,
              title: 'Wecken im Stummmodus',
              subtitle: status.silentSubtitle,
              trailing: Text(
                status.silentValue,
                style: mira.body.copyWith(fontWeight: FontWeight.w600, color: mira.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: MiraSpace.section),
        const MiraLabel('Test'),
        const SizedBox(height: MiraSpace.gap),
        MiraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Löst einen echten Alarm auf diesem Gerät aus – mit Ton, auch im Stummmodus.',
                style: mira.body.copyWith(color: mira.textSecondary),
              ),
              const SizedBox(height: 16),
              MiraButton(
                label: 'Kochelsee-Alarm testen',
                icon: Icons.notifications_active_rounded,
                onPressed: onTestKochelsee,
              ),
              const SizedBox(height: 12),
              MiraButton(
                label: 'Gardasee-Alarm testen',
                icon: Icons.notifications_active_rounded,
                onPressed: onTestGardasee,
              ),
              if (lastTestAt != null) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: MiraColors.windGood),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_lastTest(lastTestAt!, now), style: mira.caption, textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _lastTest(DateTime time, DateTime now) {
    final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
    final when = sameDay ? 'heute' : '${time.day}.${time.month}.';
    return 'Letzter Test $when ${clockLabel(time)} · ausgelöst';
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _StatusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MiraSpace.card, 12, 16, 12),
        child: Row(
          children: [
            MiraIconTile(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: mira.title.copyWith(fontSize: 16, height: 22 / 16)),
                  Text(subtitle, style: mira.caption),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
