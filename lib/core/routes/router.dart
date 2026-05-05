import 'package:expenses_tracker_new/core/routes/routes.dart';
import 'package:go_router/go_router.dart';

import '../../main.dart';
import '../../modules/analysis/presentation/screens/analysis_screen.dart';
import '../../modules/auth/presentation/screens/splash_screen.dart';
import '../../modules/auth/presentation/screens/user_name_screen.dart';
import '../../modules/contacts/presentation/screens/contacts_screen.dart';
import '../../modules/contacts/presentation/screens/group_detail_screen.dart';
import '../../modules/home/presentation/screens/collabs_screen.dart';
import '../../modules/home/presentation/screens/home_screen.dart';
import '../../modules/home/presentation/screens/more_screen.dart';
import '../../modules/settings/accounts/presentation/screens/accounts_screen.dart';
import '../../modules/settings/budget/presentation/screens/budget_list_screen.dart';
import '../../modules/settings/categories/presentation/screens/categories_screen.dart';
import '../../modules/split_bills/presentation/screens/split_bill_detail_screen.dart';
import '../../modules/split_bills/presentation/screens/split_bills_screen.dart';
import 'app_shell.dart';

final router = GoRouter(
  initialLocation: rootRoute,
  routes: [
    GoRoute(path: rootRoute, builder: (context, state) => SplashScreen()),
    GoRoute(path: loginRoute, builder: (context, state) => TestingLogin()),
    GoRoute(path: userNameRoute, builder: (context, state) => UserNameScreen()),
    GoRoute(
      path: contactsRoute,
      builder: (context, state) => ContactsScreen(),
      routes: [
        GoRoute(
          path: 'groups/:id',
          builder: (context, state) => GroupDetailScreen(
            groupId: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: analysisRoute,
      builder: (context, state) => const AnalysisScreen(),
    ),
    GoRoute(
      path: settingsCategoriesRoute,
      builder: (context, state) => const CategoriesScreen(),
    ),
    GoRoute(
      path: settingsAccountsRoute,
      builder: (context, state) => const AccountsScreen(),
    ),
    GoRoute(
      path: budgetsRoute,
      builder: (context, state) => const BudgetListScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: homeRoute,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
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
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: collabsRoute,
              builder: (context, state) => const CollabsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: moreRoute,
              builder: (context, state) => const MoreScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
