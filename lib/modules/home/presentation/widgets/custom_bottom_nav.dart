import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Pill-shaped bottom nav with floating + button in the center.
class CustomBottomNav extends StatelessWidget {
  const CustomBottomNav({
    super.key,
    this.currentIndex = 0,
    this.onTabTap,
    this.onAddTap,
  });

  final int currentIndex;
  final ValueChanged<int>? onTabTap;
  final VoidCallback? onAddTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: SizedBox(
        height: 60,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.borderDashed, width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    isSelected: currentIndex == 0,
                    onTap: () => onTabTap?.call(0),
                  ),
                  _NavItem(
                    icon: Icons.call_split,
                    label: 'Splits',
                    isSelected: currentIndex == 1,
                    onTap: () => onTabTap?.call(1),
                  ),
                  // Spacer for the floating + button
                  const SizedBox(width: 44),
                  _NavItem(
                    icon: Icons.group_rounded,
                    label: 'Collabs',
                    isSelected: currentIndex == 2,
                    onTap: () => onTabTap?.call(2),
                  ),
                  _NavItem(
                    icon: Icons.more_horiz_rounded,
                    label: 'More',
                    isSelected: currentIndex == 3,
                    onTap: () => onTabTap?.call(3),
                  ),
                ],
              ),
            ),
            Positioned(top: -8, child: _AddButton(onTap: onAddTap)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.textPrimary : AppColors.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.add, size: 22, color: AppColors.accentText),
        ),
      ),
    );
  }
}
