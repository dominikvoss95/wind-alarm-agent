import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/wind_scale.dart';
import '../utils/alarm_history.dart';
import '../utils/spot_presentation.dart';
import 'mira_controls.dart';

class ActivityDashboard extends StatefulWidget {
  final bool loading;
  final List<AlarmEntry> alarms;
  final String monitoredCaption;
  final VoidCallback onSendTest;

  const ActivityDashboard({
    super.key,
    required this.loading,
    required this.alarms,
    required this.monitoredCaption,
    required this.onSendTest,
  });

  @override
  State<ActivityDashboard> createState() => _ActivityDashboardState();
}

class _ActivityDashboardState extends State<ActivityDashboard> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final spots = widget.alarms.map((alarm) => alarm.locationId).toSet().toList();
    final visible = _filter == 'all'
        ? widget.alarms
        : widget.alarms.where((alarm) => alarm.locationId == _filter).toList();
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(MiraSpace.screen, MiraSpace.screen, MiraSpace.screen, miraBottomInset(context)),
      children: [
        Text('Verlauf', style: mira.h1),
        const SizedBox(height: 4),
        Text('Alarme der letzten 30 Tage', style: mira.body.copyWith(color: mira.textSecondary)),
        const SizedBox(height: MiraSpace.section),
        if (widget.loading)
          const _ActivitySkeleton()
        else if (visible.isEmpty)
          _EmptyAlarms(caption: widget.monitoredCaption, onSendTest: widget.onSendTest)
        else ...[
          _Filters(
            spots: spots,
            alarms: widget.alarms,
            selected: _filter,
            onSelected: (value) => setState(() => _filter = value),
          ),
          const SizedBox(height: 28),
          ..._sections(visible),
          const SizedBox(height: 16),
          Text(
            _countLabel(visible.length),
            textAlign: TextAlign.center,
            style: mira.caption,
          ),
        ],
      ],
    );
  }

  List<Widget> _sections(List<AlarmEntry> alarms) {
    final now = DateTime.now();
    final groups = <AlarmBucket, List<AlarmEntry>>{};
    for (final alarm in alarms) {
      groups.putIfAbsent(alarmBucket(alarm.at, now), () => []).add(alarm);
    }
    final widgets = <Widget>[];
    for (final bucket in AlarmBucket.values) {
      final rows = groups[bucket];
      if (rows == null || rows.isEmpty) continue;
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: MiraSpace.section));
      widgets.add(MiraLabel(alarmBucketLabel(bucket)));
      widgets.add(const SizedBox(height: MiraSpace.gap));
      for (var index = 0; index < rows.length; index++) {
        if (index > 0) widgets.add(const SizedBox(height: MiraSpace.gap));
        widgets.add(_AlarmCard(alarm: rows[index]));
      }
    }
    return widgets;
  }

  String _countLabel(int count) {
    final noun = count == 1 ? 'Alarm' : 'Alarme';
    return '$count $noun in den letzten 30 Tagen';
  }
}

class _Filters extends StatelessWidget {
  final List<String> spots;
  final List<AlarmEntry> alarms;
  final String selected;
  final ValueChanged<String> onSelected;

  const _Filters({
    required this.spots,
    required this.alarms,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final names = {for (final alarm in alarms) alarm.locationId: alarm.locationName};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChip(label: 'Alle', selected: selected == 'all', onTap: () => onSelected('all')),
        for (final spot in spots)
          _FilterChip(
            label: names[spot] ?? spot,
            selected: selected == spot,
            onTap: () => onSelected(spot),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Material(
      color: selected ? mira.accent : mira.surface2,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: mira.caption.copyWith(
              color: selected ? mira.onAccent : mira.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  final AlarmEntry alarm;

  const _AlarmCard({required this.alarm});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final color = WindScale.numberColor(alarm.knots);
    final width = (alarm.knots / 30).clamp(0.15, 1.0);
    final detail = [
      if (alarm.direction.isNotEmpty) alarm.direction,
      if (alarm.gust > 0) 'Böen ${alarm.gust.toInt()}',
    ].join(' · ');
    return MiraCard(
      padding: const EdgeInsets.symmetric(horizontal: MiraSpace.card, vertical: 16),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: mira.h2.copyWith(fontSize: 28, height: 32 / 28, fontWeight: FontWeight.w800, color: color),
                    children: [
                      TextSpan(text: alarm.knots.toInt().toString()),
                      TextSpan(
                        text: ' kts',
                        style: mira.caption.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 64 * width,
                  height: 4,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alarm.locationName, style: mira.title),
                Text(dayLabel(alarm.at), style: mira.caption),
                if (detail.isNotEmpty) Text(detail, style: mira.caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Alarm', style: mira.caption),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm_rounded, size: 16, color: mira.accent),
                  const SizedBox(width: 4),
                  Text(clockLabel(alarm.at), style: mira.title.copyWith(fontSize: 15)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyAlarms extends StatelessWidget {
  final String caption;
  final VoidCallback onSendTest;

  const _EmptyAlarms({required this.caption, required this.onSendTest});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 48, 12, 0),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mira.accent.withValues(alpha: 0.10),
              border: Border.all(color: mira.accent.withValues(alpha: 0.25)),
            ),
            child: Icon(Icons.notifications_active_rounded, color: mira.accent, size: 44),
          ),
          const SizedBox(height: 24),
          Text('Noch keine Alarme', style: mira.h2, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Sobald an einem deiner Spots Wind über deinem Minimum gemeldet wird, siehst du ihn hier.',
            style: mira.body.copyWith(color: mira.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: MiraButton(
                label: 'Test-Alarm senden',
                icon: Icons.send_rounded,
                primary: true,
                onPressed: onSendTest,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(caption, style: mira.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Bone(width: 110, height: 12),
        const SizedBox(height: 12),
        const _SkeletonCard(),
        const SizedBox(height: MiraSpace.gap),
        const _SkeletonCard(),
        const SizedBox(height: MiraSpace.section),
        const _Bone(width: 140, height: 12),
        const SizedBox(height: 12),
        const _SkeletonCard(),
        const SizedBox(height: MiraSpace.gap),
        const _SkeletonCard(),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sync_rounded, size: 16, color: context.mira.textSecondary),
            const SizedBox(width: 8),
            Text('Verlauf wird geladen …', style: context.mira.caption),
          ],
        ),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return MiraCard(
      padding: const EdgeInsets.symmetric(horizontal: MiraSpace.card, vertical: 18),
      child: const Row(
        children: [
          _Bone(width: 56, height: 44),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bone(width: 140, height: 16),
                SizedBox(height: 10),
                _Bone(width: 180, height: 12),
              ],
            ),
          ),
          SizedBox(width: 12),
          _Bone(width: 48, height: 14),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  final double width;
  final double height;

  const _Bone({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(colors: [MiraColors.surface2, MiraColors.outline, MiraColors.surface2]),
      ),
    );
  }
}
