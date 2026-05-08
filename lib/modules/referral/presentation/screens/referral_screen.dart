import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;

import '../../../../core/theme/app_colors.dart';
import '../../data/models/referral_stats.dart';
import '../../providers/referral_provider.dart';

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(referralStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'Refer & Earn',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(
          child: Text('Failed to load referral data', style: TextStyle(color: AppColors.textSecondary)),
        ),
        data: (stats) => _ReferralContent(stats: stats),
      ),
    );
  }
}

class _ReferralContent extends StatelessWidget {
  const _ReferralContent({required this.stats});

  final ReferralStats stats;

  void _copyCode(BuildContext context) {
    Clipboard.setData(ClipboardData(text: stats.referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Referral code copied!')),
    );
  }

  void _shareCode() {
    SharePlus.instance.share(
      ShareParams(
        text: 'Join me on Spendz! Use my referral code ${stats.referralCode} when you sign up. '
            "You'll help me unlock free premium days 🎉",
        subject: 'Join Spendz with my referral code',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _CodeCard(stats: stats, onCopy: () => _copyCode(context), onShare: _shareCode),
        const SizedBox(height: 24),
        _StatsCard(stats: stats),
        const SizedBox(height: 24),
        _HowItWorksCard(),
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.stats, required this.onCopy, required this.onShare});

  final ReferralStats stats;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            'Your referral code',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            stats.referralCode,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Share'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final ReferralStats stats;

  @override
  Widget build(BuildContext context) {
    final bonusExpiresAt = stats.bonusExpiresAt;
    final hasBonusActive =
        bonusExpiresAt != null && bonusExpiresAt.isAfter(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your stats',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'Friends referred',
                  value: '${stats.totalReferrals}',
                  icon: Icons.people_rounded,
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'Days earned',
                  value: '${stats.totalDaysEarned}',
                  icon: Icons.calendar_today_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${stats.progressInCurrentMilestone}/5 towards next 7 days',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              Text(
                '${stats.referralsUntilNext} more to go',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.progressInCurrentMilestone / 5,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          if (hasBonusActive) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, size: 16, color: AppColors.budgetOverallBar),
                const SizedBox(width: 8),
                Text(
                  'Referral premium active until ${DateFormat('d MMM yyyy').format(bonusExpiresAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.share_rounded, 'Share your code with friends'),
      (Icons.person_add_rounded, 'They enter it when signing up'),
      (Icons.workspace_premium_rounded, 'Every 5 referrals earns you 7 free premium days'),
      (Icons.all_inclusive_rounded, 'No cap — every 5 referrals keeps adding 7 more days'),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(step.$1, size: 18, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
