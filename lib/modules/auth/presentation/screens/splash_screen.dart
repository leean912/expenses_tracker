import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/widgets/custom_lottie_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/states/auth_state.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (prev, next) {
      if (prev != next) {
        next.whenOrNull(
          authenticated: (user) async {
            // await Future.delayed(const Duration(seconds: 3));
            if (!context.mounted) return;
            if (user.username == null) {
              context.pushReplacement(userNameRoute);
            } else {
              context.pushReplacement(homeRoute);
            }
          },
          unauthenticated: () async {
            // await Future.delayed(const Duration(seconds: 3));
            if (context.mounted) context.pushReplacement(loginRoute);
          },
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CustomDotLottieWidget(
          lottiePath: 'assets/lottie/splash_screen.lottie',
          width: 300,
          height: 300,
        ),
      ),
    );
  }
}
