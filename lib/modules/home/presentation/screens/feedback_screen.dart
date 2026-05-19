import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';

enum _FeedbackType {
  bug('Bug Report'),
  featureRequest('Feature Request'),
  enhancement('Enhancement'),
  subscription('Subscription'),
  general('General Feedback');

  const _FeedbackType(this.label);
  final String label;
}

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  _FeedbackType _selectedType = _FeedbackType.bug;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final subject = Uri.encodeComponent(
      '[${_selectedType.label}] ${_titleController.text.trim()}',
    );
    final body = Uri.encodeComponent(_descriptionController.text.trim());
    final uri = Uri.parse(
      'mailto:jomeatdeveloper@gmail.com?subject=$subject&body=$body',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      if (mounted) context.pop();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app found on this device.')),
        );
      }
    }

    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'Feedback',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            const Text(
              'We\'d love to hear from you. Your feedback helps us improve JomSpendz.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'You can also email us directly at jomeatdeveloper@gmail.com',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Type',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<_FeedbackType>(
              initialValue: _selectedType,
              dropdownColor: AppColors.surface,
              decoration: _inputDecoration(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              items: _FeedbackType.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedType = v);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Title',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _titleController,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: _inputDecoration(hint: 'Brief summary'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Description',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _descriptionController,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: _inputDecoration(hint: 'Tell us more…'),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 6,
              minLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Description is required'
                  : null,
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentText,
                  disabledBackgroundColor: AppColors.accent.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accentText,
                        ),
                      )
                    : const Text(
                        'Send Feedback',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.expenseLight),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.expenseLight, width: 1.5),
      ),
    );
  }
}
