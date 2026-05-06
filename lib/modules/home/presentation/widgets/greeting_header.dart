import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Top header showing user's name + notification bell + profile avatar.
///
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    this.userName = 'Alice',
    this.displayName,
    this.isPremium = false,
    this.onBellTap,
    this.onAvatarTap,
  });

  final String userName;
  final String? displayName;
  final bool isPremium;
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
                Row(
                  children: [
                    Text(
                      'Hello, ',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$displayName',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (isPremium) ...[
                      const SizedBox(width: 6),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 15,
                            color: AppColors.premiumStatus,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Pro',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.premiumStatus,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                if (displayName != null)
                  Text(
                    '@$userName',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
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
            icon: Icons.group_add,
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
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}
