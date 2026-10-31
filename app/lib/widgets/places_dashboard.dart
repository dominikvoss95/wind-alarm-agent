import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/location.dart';
import '../theme/app_theme.dart';
import '../utils/spot_presentation.dart';
import 'mira_controls.dart';

class PlacesDashboard extends StatelessWidget {
  final List<bool> armed;
  final ValueChanged<WindLocation> onOpen;

  const PlacesDashboard({super.key, required this.armed, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final locations = WindLocation.values;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(MiraSpace.screen, MiraSpace.screen, MiraSpace.screen, miraBottomInset(context)),
      children: [
        Text('Orte', style: mira.h1),
        const SizedBox(height: 4),
        Text('Spots und ihre Überwachung', style: mira.body.copyWith(color: mira.textSecondary)),
        const SizedBox(height: 24),
        MiraGroup(
          rows: [
            for (var index = 0; index < locations.length; index++)
              _PlaceRow(
                data: appLocations[locations[index]]!,
                armed: index < armed.length && armed[index],
                onTap: () => onOpen(locations[index]),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  final LocationData data;
  final bool armed;
  final VoidCallback onTap;

  const _PlaceRow({required this.data, required this.armed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MiraSpace.card, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: mira.surface2,
                  borderRadius: BorderRadius.circular(MiraSpace.radiusIcon),
                ),
                child: Center(child: FaIcon(data.icon, color: mira.accent, size: 16)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.name, style: mira.title.copyWith(fontSize: 16, height: 22 / 16)),
                    Text(
                      '${armed ? 'Überwachung aktiv' : 'Standby'} · ${displayWindow(data.activeWindow)}',
                      style: mira.caption,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: mira.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
