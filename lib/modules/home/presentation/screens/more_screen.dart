import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/providers/states/auth_state.dart';
import '../../../subscription/providers/subscription_provider.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    final user = ref
        .watch(authProvider)
        .maybeWhen(authenticated: (user) => user, orElse: () => null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          children: [
            if (user != null) ...[
              _ProfileTile(
                displayName: user.displayName,
                username: user.username,
                email: user.email,
                onTap: () => context.push(profileRoute),
              ),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.xl),
            ],
            const _SectionHeader('Subscription'),
            ListTile(
              leading: Icon(
                Icons.workspace_premium_rounded,
                color: isPremium
                    ? AppColors.budgetOverallBar
                    : AppColors.textSecondary,
              ),
              title: Text(
                isPremium ? 'Spendz Pro' : 'Upgrade to Pro',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                isPremium ? 'Active' : 'Unlock all features',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: isPremium
                  ? () => paymentService.presentCustomerCenter()
                  : () => context.push(paywallRoute),
            ),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: AppSpacing.xl),
            const _SectionHeader('Referral'),
            ListTile(
              leading: const Icon(
                Icons.card_giftcard_rounded,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Refer & Earn',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: const Text(
                'Refer 5 friends, earn 7 free premium days',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: () => context.push(referralRoute),
            ),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: AppSpacing.xl),
            const _SectionHeader('Settings'),
            ListTile(
              leading: const Icon(
                Icons.repeat_rounded,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Recurring',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: () => context.push(recurringRoute),
            ),
            const Divider(height: 1, indent: 56, color: AppColors.border),
            ListTile(
              leading: const Icon(
                Icons.grid_view_rounded,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Categories',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: () => context.push(settingsCategoriesRoute),
            ),
            const Divider(height: 1, indent: 56, color: AppColors.border),
            ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Accounts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: () => context.push(settingsAccountsRoute),
            ),
            const Divider(height: 1, indent: 56, color: AppColors.border),
            ListTile(
              leading: const Icon(
                Icons.savings_outlined,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Budgets',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: () => context.push(budgetsRoute),
            ),
            const Divider(height: 1, indent: 56, color: AppColors.border),
            ListTile(
              leading: const Icon(
                Icons.picture_as_pdf_rounded,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Export PDF / Excel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: const Text(
                'Export your transactions as PDF or Excel',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: () {
                context.push(exportPdfRoute);
              },
            ),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: AppSpacing.xl),
            const _SectionHeader('Legal'),
            ListTile(
              leading: const Icon(
                Icons.privacy_tip_outlined,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
              onTap: () => context.push(privacyPolicyRoute),
            ),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: AppSpacing.xl),
            const _SectionHeader('Account'),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.expenseLight),
              title: const Text(
                'Log out',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.expenseLight,
                ),
              ),
              onTap: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.displayName,
    required this.username,
    required this.email,
    required this.onTap,
  });

  final String? displayName;
  final String? username;
  final String email;
  final VoidCallback onTap;

  String _initials() {
    final name = displayName ?? email;
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      leading: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            _initials(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.accentText,
            ),
          ),
        ),
      ),
      title: Text(
        displayName ?? email,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: username != null
          ? Text(
              '@$username',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            )
          : null,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
