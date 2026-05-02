import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class CollabsScreen extends StatelessWidget {
  const CollabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text(
          'Collabs',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
