import 'package:expenses_tracker_new/core/routes/routes.dart';
import 'package:expenses_tracker_new/modules/auth/providers/auth_provider.dart';
import 'package:expenses_tracker_new/service_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/routes/router.dart';
import 'core/theme/app_colors.dart';
import 'modules/auth/providers/states/auth_state.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: env.supabaseApiUrl,
    anonKey: env.supabaseApiKey,
  );

  runApp(ProviderScope(child: const MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: ThemeData(
        useMaterial3: true,
        // Set system font; SF Pro on iOS, Roboto on Android.
        // For custom fonts, add to pubspec.yaml + theme.
        fontFamily: 'system-ui',
        scaffoldBackgroundColor: AppColors.background,
        textTheme: const TextTheme(
          // Tighter line heights for compact mobile UIs
          bodyMedium: TextStyle(height: 1.3),
          bodyLarge: TextStyle(height: 1.3),
        ),
      ),
      routerConfig: router,
    );
  }
}

class TestingLogin extends ConsumerWidget {
  const TestingLogin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (prev, next) {
      if (prev != next) {
        next.whenOrNull(
          authenticated: (user) {
            context.pushReplacement(homeRoute);
          },
        );
      }
    });

    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            ref.read(authProvider.notifier).login();
          },
          child: const Text('Login with Google'),
        ),
      ),
    );
  }
}
