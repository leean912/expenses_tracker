import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../providers/subscription_provider.dart';

final _offeringsProvider = FutureProvider.autoDispose<Offerings>((ref) {
  return Purchases.getOfferings();
});

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Package? _selectedPackage;
  bool _isPurchasing = false;

  static const _features = [
    (Icons.all_inclusive_rounded, 'Unlimited categories'),
    (Icons.account_balance_wallet_rounded, 'Unlimited accounts'),
    (Icons.group_rounded, 'Unlimited groups'),
    (Icons.document_scanner_rounded, 'Receipt OCR scanning'),
    (Icons.currency_exchange_rounded, 'Live FX rates'),
    (Icons.download_rounded, 'Data export (CSV & PDF)'),
    (Icons.repeat_rounded, 'Unlimited recurring expenses'),
    (Icons.repeat_one_rounded, 'Unlimited recurring split bills'),
    (Icons.photo_camera_rounded, 'Receipt photo storage'),
  ];

  void _onOfferingsLoaded(Offerings offerings) {
    if (_selectedPackage != null) return;
    final packages = offerings.current?.availablePackages ?? [];
    final annual = packages
        .where((p) => p.packageType == PackageType.annual)
        .firstOrNull;
    setState(() => _selectedPackage = annual ?? packages.firstOrNull);
  }

  Future<void> _purchase() async {
    final pkg = _selectedPackage;
    if (pkg == null || _isPurchasing) return;
    setState(() => _isPurchasing = true);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(pkg));
      final isActive =
          result.customerInfo.entitlements.active['spendz Pro'] != null;
      if (isActive) {
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) unawaited(syncSubscriptionTier(userId));
        ref.invalidate(subscriptionProvider);
        if (mounted) context.pop();
      }
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message ?? 'Purchase failed')));
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _isPurchasing = true);
    try {
      await Purchases.restorePurchases();
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) unawaited(syncSubscriptionTier(userId));
      ref.invalidate(subscriptionProvider);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nothing to restore')));
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offeringsAsync = ref.watch(_offeringsProvider);
    offeringsAsync.whenData(_onOfferingsLoaded);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildHeader(context),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: AppSpacing.xxl),
                ..._features.map((f) => _FeatureRow(icon: f.$1, label: f.$2)),
                const _FutureFeatureRow(),
                const SizedBox(height: AppSpacing.xxl),
                _buildPackageSection(offeringsAsync),
                const SizedBox(height: AppSpacing.xl),
                _buildPurchaseButton(),
                const SizedBox(height: AppSpacing.lg),
                _buildRestoreButton(),
                const SizedBox(height: AppSpacing.xxl),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: const Color(0xFF1A1A18),
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white70),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C2410), Color(0xFF1A1A18)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.premiumStatus.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.premiumStatus.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: AppColors.premiumStatus,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Spendz Pro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Everything unlimited, forever',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPackageSection(AsyncValue<Offerings> offeringsAsync) {
    return offeringsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, _) => const Center(
        child: Text(
          'Failed to load plans',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
      data: (offerings) {
        final packages = offerings.current?.availablePackages ?? [];
        if (packages.isEmpty) {
          return const Center(child: Text('No plans available'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a plan',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ...packages.map(
              (pkg) => _PackageCard(
                package: pkg,
                isSelected: _selectedPackage?.identifier == pkg.identifier,
                onTap: () => setState(() => _selectedPackage = pkg),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPurchaseButton() {
    final pkg = _selectedPackage;
    final label = pkg == null
        ? 'Select a plan'
        : 'Get ${_packageLabel(pkg.packageType)}';

    return FilledButton(
      onPressed: (_isPurchasing || pkg == null) ? null : _purchase,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.accentText,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      child: _isPurchasing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
    );
  }

  Widget _buildRestoreButton() {
    return Center(
      child: TextButton(
        onPressed: _isPurchasing ? null : _restore,
        child: const Text(
          'Restore purchases',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }

  String _packageLabel(PackageType type) => switch (type) {
    PackageType.monthly => 'Monthly',
    PackageType.annual => 'Annual',
    PackageType.lifetime => 'Lifetime',
    _ => 'Plan',
  };
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.positiveDark.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 16, color: AppColors.positiveDark),
          ),
          const SizedBox(width: AppSpacing.lg),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FutureFeatureRow extends StatelessWidget {
  const _FutureFeatureRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.premiumStatus.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: AppColors.premiumStatus,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          const Text(
            'All future premium features',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.premiumStatus,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.isSelected,
    required this.onTap,
  });

  final Package package;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAnnual = package.packageType == PackageType.annual;
    final isLifetime = package.packageType == PackageType.lifetime;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
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
                          _title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: isSelected
                                ? AppColors.accentText
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (isAnnual) ...[
                          const SizedBox(width: AppSpacing.md),
                          const _Badge(
                            label: 'Save ~30%',
                            color: AppColors.premiumStatus,
                          ),
                        ],
                        if (isLifetime) ...[
                          const SizedBox(width: AppSpacing.md),
                          const _Badge(
                            label: 'Best value',
                            color: AppColors.premiumStatus,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? AppColors.accentText.withValues(alpha: 0.65)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                package.storeProduct.priceString,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: isSelected
                      ? AppColors.accentText
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _title => switch (package.packageType) {
    PackageType.monthly => 'Monthly',
    PackageType.annual => 'Annual',
    PackageType.lifetime => 'Lifetime',
    _ => package.identifier,
  };

  String get _subtitle => switch (package.packageType) {
    PackageType.monthly => 'Billed monthly',
    PackageType.annual => 'Billed yearly',
    PackageType.lifetime => 'One-time payment',
    _ => '',
  };
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
