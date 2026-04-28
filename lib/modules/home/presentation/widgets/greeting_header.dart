import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Top header showing user's name + notification bell + profile avatar.
///
/// TODO: pass real user data via constructor or watch from a profileProvider.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    this.userName = 'Alice',
    this.onBellTap,
    this.onAvatarTap,
  });

  final String userName;
  final VoidCallback? onBellTap;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello,',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          _CircleIconButton(
            background: AppColors.entertainmentLight,
            iconColor: AppColors.entertainmentDark,
            icon: Icons.notifications_none_rounded,
            onTap: onBellTap,
          ),
          const SizedBox(width: AppSpacing.md),
          _CircleIconButton(
            background: AppColors.foodLight,
            iconColor: AppColors.foodDark,
            icon: Icons.person_rounded,
            onTap: onAvatarTap,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.background,
    required this.iconColor,
    required this.icon,
    this.onTap,
  });

  final Color background;
  final Color iconColor;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}
