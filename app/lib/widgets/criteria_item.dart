import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'compass.dart';
import 'mira_controls.dart';

class CriteriaRow {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Set<String>? sectors;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitch;
  final bool showChevron;

  const CriteriaRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.sectors,
    this.switchValue,
    this.onSwitch,
    this.showChevron = true,
  });
}

class CriteriaGroup extends StatelessWidget {
  final String title;
  final List<CriteriaRow> rows;

  const CriteriaGroup({super.key, required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.mira.h2),
        const SizedBox(height: MiraSpace.gap),
        MiraGroup(
          rows: [for (final row in rows) _CriteriaTile(row: row)],
        ),
      ],
    );
  }
}

class _CriteriaTile extends StatelessWidget {
  final CriteriaRow row;

  const _CriteriaTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final hasSwitch = row.switchValue != null && row.onSwitch != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MiraSpace.card, 12, 8, 12),
        child: Row(
          children: [
            MiraIconTile(icon: row.icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(row.title, style: mira.title.copyWith(fontSize: 16, height: 22 / 16)),
                  Text(row.subtitle, style: mira.caption),
                ],
              ),
            ),
            if (row.sectors != null) ...[
              const SizedBox(width: 8),
              SectorCompass(sectors: row.sectors!),
            ] else if (row.value != null && !hasSwitch)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  row.value!,
                  style: mira.body.copyWith(fontWeight: FontWeight.w600, color: mira.textSecondary),
                ),
              ),
            if (hasSwitch)
              MiraSwitch(value: row.switchValue!, onChanged: row.onSwitch!)
            else if (row.showChevron)
              Icon(Icons.chevron_right_rounded, color: mira.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }
}
