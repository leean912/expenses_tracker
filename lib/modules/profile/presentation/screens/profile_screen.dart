import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/providers/states/auth_state.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _displayNameController;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref
        .read(authProvider)
        .maybeWhen(authenticated: (user) => user, orElse: () => null);
    _displayNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _displayNameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(authProvider.notifier).updateDisplayName(name);
      setState(() => _isEditing = false);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _cancel(String originalName) {
    _displayNameController.text = originalName;
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.maybeWhen(
      authenticated: (user) => user,
      orElse: () => null,
    );

    if (user == null) {
      context.pop();
      return const SizedBox.shrink();
    }

    final initials = _initials(user.displayName ?? user.email);
    final memberSince = user.createdAt != null
        ? DateFormat('MMMM yyyy').format(user.createdAt!)
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentText,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _SectionHeader('Personal'),
          _DisplayNameTile(
            controller: _displayNameController,
            isEditing: _isEditing,
            isSaving: _isSaving,
            originalName: user.displayName ?? '',
            onEdit: () => setState(() => _isEditing = true),
            onSave: _save,
            onCancel: () => _cancel(user.displayName ?? ''),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.border),
          _ReadOnlyTile(
            icon: Icons.alternate_email_rounded,
            label: 'Username',
            value: user.username != null ? '@${user.username}' : '—',
          ),
          const Divider(height: 1, indent: 56, color: AppColors.border),
          _ReadOnlyTile(
            icon: Icons.email_outlined,
            label: 'Email',
            value: user.email,
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.xl),
          const _SectionHeader('Account'),
          _ReadOnlyTile(
            icon: Icons.language_rounded,
            label: 'Default currency',
            value: user.defaultCurrency,
          ),
          if (memberSince != null) ...[
            const Divider(height: 1, indent: 56, color: AppColors.border),
            _ReadOnlyTile(
              icon: Icons.calendar_today_rounded,
              label: 'Register since',
              value: memberSince,
            ),
          ],
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _DisplayNameTile extends StatelessWidget {
  const _DisplayNameTile({
    required this.controller,
    required this.isEditing,
    required this.isSaving,
    required this.originalName,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController controller;
  final bool isEditing;
  final bool isSaving;
  final String originalName;
  final VoidCallback onEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(
        Icons.person_outline_rounded,
        color: AppColors.textSecondary,
      ),
      title: const Text(
        'Display name',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      subtitle: isEditing
          ? TextField(
              controller: controller,
              autofocus: true,
              maxLength: 30,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                counterText: '',
              ),
              onSubmitted: (_) => onSave(),
            )
          : Text(
              controller.text.isEmpty ? '—' : controller.text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
      trailing: isEditing
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                    onPressed: onCancel,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.check_rounded,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                    onPressed: onSave,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ],
            )
          : IconButton(
              icon: const Icon(
                Icons.edit_outlined,
                color: AppColors.textTertiary,
                size: 18,
              ),
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
      isThreeLine: false,
    );
  }
}

class _ReadOnlyTile extends StatelessWidget {
  const _ReadOnlyTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
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
