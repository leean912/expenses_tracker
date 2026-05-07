import 'package:expenses_tracker_new/modules/auth/providers/states/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modules/auth/providers/auth_provider.dart';
import '../../modules/expenses/presentation/widgets/add_expense_sheet.dart';
import '../../modules/home/presentation/widgets/custom_bottom_nav.dart';
import 'routes.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _showAddExpenseSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddExpenseSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (prev, next) {
      next.whenOrNull(
        unauthenticated: () {
          if (context.mounted) context.go(loginRoute);
        },
      );
    });
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: CustomBottomNav(
          currentIndex: navigationShell.currentIndex,
          onTabTap: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          onAddTap: () => _showAddExpenseSheet(context),
        ),
      ),
    );
  }
}
