import 'package:expenses_tracker_new/core/routes/routes.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../../modules/auth/presentation/screens/splash_screen.dart';
import '../../modules/home/presentation/screens/home_screen.dart';

final router = GoRouter(
  initialLocation: rootRoute,
  routes: [
    GoRoute(path: rootRoute, builder: (context, state) => SplashScreen()),
    GoRoute(path: loginRoute, builder: (context, state) => TestingLogin()),
    GoRoute(path: homeRoute, builder: (context, state) => HomeScreen()),
  ],
);
