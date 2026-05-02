import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../modules/expenses/presentation/widgets/add_expense_sheet.dart';
import '../../modules/home/presentation/widgets/custom_bottom_nav.dart';

class AppShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
