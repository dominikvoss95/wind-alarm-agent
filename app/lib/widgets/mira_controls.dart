import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

double miraBottomInset(BuildContext context) {
  return 16 + MediaQuery.paddingOf(context).bottom + MiraSpace.navHeight + 24;
}

class MiraLabel extends StatelessWidget {
  final String text;
  final Color? color;

  const MiraLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: context.mira.label.copyWith(color: color ?? context.mira.textSecondary),
    );
  }
}

class MiraSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const MiraSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Semantics(
      button: true,
      toggled: value,
      label: 'Überwachung',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: MiraSpace.touch,
          height: MiraSpace.touch,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 36,
              height: 22,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? mira.accent : mira.surface2,
                borderRadius: BorderRadius.circular(11),
                border: value ? null : Border.all(color: mira.outline),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: value ? mira.onAccent : mira.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MiraButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  const MiraButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final foreground = primary ? mira.onAccent : mira.accent;
    return SizedBox(
      width: double.infinity,
      height: MiraSpace.buttonHeight,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: primary ? mira.accent : mira.accent.withValues(alpha: 0.06),
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: primary ? BorderSide.none : BorderSide(color: mira.accent, width: 1.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mira.body.copyWith(fontWeight: FontWeight.w700, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MiraPill extends StatelessWidget {
  final String label;
  final Color color;
  final Widget? leading;

  const MiraPill({super.key, required this.label, required this.color, this.leading});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: MiraColors.pillTint),
        borderRadius: BorderRadius.circular(MiraSpace.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ??
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.mira.caption.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class MiraCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final bool bordered;

  const MiraCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        shape: CircleBorder(
          side: bordered ? BorderSide(color: context.mira.outline) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: MiraSpace.touch,
            height: MiraSpace.touch,
            child: Icon(icon, color: context.mira.textPrimary, size: 24),
          ),
        ),
      ),
    );
  }
}

class MiraIconTile extends StatelessWidget {
  final IconData icon;

  const MiraIconTile({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: context.mira.surface2,
        borderRadius: BorderRadius.circular(MiraSpace.radiusIcon),
      ),
      child: Icon(icon, color: context.mira.accent, size: 19),
    );
  }
}

class MiraGroup extends StatelessWidget {
  final List<Widget> rows;

  const MiraGroup({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.mira.surface,
        borderRadius: BorderRadius.circular(MiraSpace.radius),
        border: Border.all(color: context.mira.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.only(left: 62),
                child: Container(height: 1, color: context.mira.outline),
              ),
            rows[index],
          ],
        ],
      ),
    );
  }
}

class MiraCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const MiraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MiraSpace.card),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.mira.surface,
        borderRadius: BorderRadius.circular(MiraSpace.radius),
        border: Border.all(color: context.mira.outline),
      ),
      child: child,
    );
  }
}
