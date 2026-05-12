import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jomspendz/service_locator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/routes/router.dart';
import 'core/theme/app_colors.dart';
import 'firebase_options.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: env.supabaseApiUrl,
    anonKey: env.supabaseApiKey,
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await paymentService.initialize();

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
