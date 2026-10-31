import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MiraScaffold extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final Widget body;
  final bool padTop;

  const MiraScaffold({
    super.key,
    required this.index,
    required this.onChanged,
    required this.body,
    this.padTop = true,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final bottom = 16 + MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: mira.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: padTop ? SafeArea(bottom: false, child: body) : body,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 150,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      mira.bg.withValues(alpha: 0),
                      mira.bg.withValues(alpha: 0.92),
                      mira.bg,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom,
            child: MiraBottomNav(index: index, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class MiraBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const MiraBottomNav({super.key, required this.index, required this.onChanged});

  static const _items = [
    (icon: Icons.home_rounded, label: 'Start'),
    (icon: Icons.location_on_rounded, label: 'Orte'),
    (icon: Icons.insights_rounded, label: 'Verlauf'),
    (icon: Icons.settings_rounded, label: 'Setup'),
  ];

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Container(
      height: MiraSpace.navHeight,
      decoration: BoxDecoration(
        color: mira.surface2.withValues(alpha: MiraColors.navFill),
        borderRadius: BorderRadius.circular(MiraSpace.radiusNav),
        border: Border.all(color: mira.outline),
        boxShadow: const [
          BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: _NavItem(
                icon: _items[i].icon,
                label: _items[i].label,
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final color = selected ? mira.accent : mira.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MiraSpace.radiusNav),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? mira.accent.withValues(alpha: MiraColors.navIconTint) : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: mira.label.copyWith(
                fontSize: 12,
                height: 16 / 12,
                letterSpacing: 0,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
