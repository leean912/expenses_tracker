import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/user_name_provider.dart';

class UserNameScreen extends ConsumerStatefulWidget {
  const UserNameScreen({super.key});

  @override
  ConsumerState<UserNameScreen> createState() => _UserNameScreenState();
}

class _UserNameScreenState extends ConsumerState<UserNameScreen> {
  final _usernameController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userNameProvider);
    final notifier = ref.read(userNameProvider.notifier);

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
                'Choose a username',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This is how others will find you. You can\'t change it later.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 40),
              _UsernameField(
                controller: _usernameController,
                state: state,
                onChanged: notifier.onUsernameChanged,
              ),
              const SizedBox(height: 8),
              _FeedbackText(state: state),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.red),
                ),
              ],
              const Spacer(),
              _SubmitButton(
                state: state,
                notifier: notifier,
                onPressed: () async {
                  final ok = await notifier.submit(
                    _usernameController.text.trim(),
                  );
                  if (!context.mounted) return;
                  if (ok) context.pushReplacement(referralOnboardingRoute);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsernameField extends StatelessWidget {
  const _UsernameField({
    required this.controller,
    required this.state,
    required this.onChanged,
  });

  final TextEditingController controller;
  final UserNameState state;
  final ValueChanged<String> onChanged;

  Color get _borderColor => switch (state.availability) {
    UsernameAvailability.available => const Color(0xFF3B6D11),
    UsernameAvailability.taken || UsernameAvailability.invalid => Colors.red,
    _ => AppColors.border,
  };

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (v) => onChanged(v.trim()),
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'e.g. alice_123',
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        prefixText: '@',
        prefixStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        suffixIcon: state.availability == UsernameAvailability.checking
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: _borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: _borderColor, width: 1.5),
        ),
      ),
    );
  }
}

class _FeedbackText extends StatelessWidget {
  const _FeedbackText({required this.state});

  final UserNameState state;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (state.availability) {
      UsernameAvailability.available => (
        'Username is available',
        const Color(0xFF3B6D11),
      ),
      UsernameAvailability.taken => ('Username is already taken', Colors.red),
      UsernameAvailability.invalid => (
        '3–20 chars, lowercase letters, numbers, underscores only',
        Colors.red,
      ),
      _ => ('', AppColors.textTertiary),
    };

    if (text.isEmpty) return const SizedBox.shrink();

    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.state,
    required this.notifier,
    required this.onPressed,
  });

  final UserNameState state;
  final UserNameNotifier notifier;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: notifier.canSubmit ? onPressed : null,
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
    );
  }
}
