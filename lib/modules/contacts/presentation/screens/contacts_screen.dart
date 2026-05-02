import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/contact_model.dart';
import '../../providers/contacts_provider.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _adding = false;
  final Set<String> _dismissedIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _submitAdd() async {
    final identifier = _searchController.text.trim();
    if (identifier.isEmpty) return;
    setState(() => _adding = true);
    final error = await ref
        .read(contactsProvider.notifier)
        .addContact(identifier);
    if (!mounted) return;
    setState(() => _adding = false);
    if (error == null) {
      _searchController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
        ),
      );
    }
  }

  Future<void> _handleDelete(String contactId, String label) async {
    setState(() => _dismissedIds.add(contactId));
    await ref.read(contactsProvider.notifier).deleteContact(contactId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label removed.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Contacts',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search or add by username…',
                        hintStyle: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.textTertiary,
                          size: 18,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _submitAdd(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                GestureDetector(
                  onTap: _adding ? null : _submitAdd,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: _adding
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accentText,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.person_add_rounded,
                            color: AppColors.accentText,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: contactsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Failed to load contacts.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => ref.invalidate(contactsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (contacts) {
                final filtered = contacts
                    .where((c) => !_dismissedIds.contains(c.id))
                    .where(
                      (c) =>
                          _query.isEmpty ||
                          c.displayLabel.toLowerCase().contains(_query),
                    )
                    .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No contacts yet.\nSearch a username to add.'
                          : 'No results for "$_query".',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.sm,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final contact = filtered[index];
                    return _ContactTile(
                      contact: contact,
                      onDelete: () =>
                          _handleDelete(contact.id, contact.displayLabel),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onDelete});

  final ContactModel contact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(contact.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEB),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFF993C1D),
          size: 20,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _Avatar(label: contact.displayLabel),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (contact.username != null)
                    Text(
                      '@${contact.username}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
