import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/referral_onboarding_provider.dart';

class ReferralOnboardingScreen extends ConsumerStatefulWidget {
  const ReferralOnboardingScreen({super.key});

  @override
  ConsumerState<ReferralOnboardingScreen> createState() =>
      _ReferralOnboardingScreenState();
}

class _ReferralOnboardingScreenState
    extends ConsumerState<ReferralOnboardingScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final notifier = ref.read(referralOnboardingProvider.notifier);
    final state = ref.read(referralOnboardingProvider);
    if (state.isPartial) return;
    final ok = await notifier.submit();
    if (!mounted) return;
    if (ok) context.pushReplacement(homeRoute);
  }

  void _skip() => context.pushReplacement(homeRoute);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referralOnboardingProvider);
    final notifier = ref.read(referralOnboardingProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text(
                'Got a referral code?',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a friend\'s code to give them a reward. You can skip this step.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Referral code',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _controller,
                onChanged: notifier.onCodeChanged,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _continue(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. AB3X7K2M',
                  hintStyle: const TextStyle(
                    color: AppColors.textTertiary,
                    letterSpacing: 1,
                    fontWeight: FontWeight.normal,
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(
                      color: (state.isPartial || state.error != null)
                          ? Colors.red
                          : AppColors.border,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(
                      color: (state.isPartial || state.error != null)
                          ? Colors.red
                          : AppColors.accent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              if (state.isPartial) ...[
                const SizedBox(height: 6),
                Text(
                  'Must be exactly 8 letters and numbers',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red,
                  ),
                ),
              ] else if (state.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  state.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: state.isSubmitting ? null : _continue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor: AppColors.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: state.isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            color: AppColors.accentText,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: state.isSubmitting ? null : _skip,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
