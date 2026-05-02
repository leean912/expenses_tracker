import 'package:expenses_tracker_new/core/routes/routes.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../../modules/auth/presentation/screens/splash_screen.dart';
import '../../modules/auth/presentation/screens/user_name_screen.dart';
import '../../modules/contacts/presentation/screens/contacts_screen.dart';
import '../../modules/home/presentation/screens/home_screen.dart';
import '../../modules/split_bills/presentation/screens/split_bill_detail_screen.dart';
import '../../modules/split_bills/presentation/screens/split_bills_screen.dart';

final router = GoRouter(
  initialLocation: rootRoute,
  routes: [
    GoRoute(path: rootRoute, builder: (context, state) => SplashScreen()),
    GoRoute(path: loginRoute, builder: (context, state) => TestingLogin()),
    GoRoute(path: homeRoute, builder: (context, state) => HomeScreen()),
    GoRoute(path: userNameRoute, builder: (context, state) => UserNameScreen()),
    GoRoute(path: contactsRoute, builder: (context, state) => ContactsScreen()),
    GoRoute(
      path: splitBillsRoute,
      builder: (context, state) => const SplitBillsScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => SplitBillDetailScreen(
            billId: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ],
);
