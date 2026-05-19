import 'package:go_router/go_router.dart';
import 'package:jomspendz/core/routes/routes.dart';

import '../../modules/analysis/presentation/screens/analysis_screen.dart';
import '../../modules/analysis/presentation/screens/budget_analytics_screen.dart';
import '../../modules/auth/presentation/screens/consent_screen.dart';
import '../../modules/auth/presentation/screens/force_update_screen.dart';
import '../../modules/auth/presentation/screens/login_screen.dart';
import '../../modules/auth/presentation/screens/referral_onboarding_screen.dart';
import '../../modules/auth/presentation/screens/splash_screen.dart';
import '../../modules/auth/presentation/screens/user_name_screen.dart';
import '../../modules/collabs/data/models/collab_model.dart';
import '../../modules/collabs/presentation/screens/collab_analysis_screen.dart';
import '../../modules/collabs/presentation/screens/collab_detail_screen.dart';
import '../../modules/collabs/presentation/screens/collab_members_screen.dart';
import '../../modules/contacts/presentation/screens/contacts_screen.dart';
import '../../modules/contacts/presentation/screens/group_detail_screen.dart';
import '../../modules/export/presentation/screens/export_screen.dart';
import '../../modules/home/presentation/screens/category_expenses_screen.dart';
import '../../modules/home/presentation/screens/feedback_screen.dart';
import '../../modules/home/presentation/screens/collabs_screen.dart';
import '../../modules/home/presentation/screens/home_screen.dart';
import '../../modules/home/presentation/screens/more_screen.dart';
import '../../modules/profile/presentation/screens/profile_screen.dart';
import '../../modules/recurring/data/models/recurring_expense_model.dart';
import '../../modules/recurring/data/models/recurring_split_bill_model.dart';
import '../../modules/recurring/presentation/screens/recurring_expense_form_screen.dart';
import '../../modules/recurring/presentation/screens/recurring_list_screen.dart';
import '../../modules/recurring/presentation/screens/recurring_split_bill_form_screen.dart';
import '../../modules/referral/presentation/screens/referral_screen.dart';
import '../../modules/settings/accounts/presentation/screens/accounts_screen.dart';
import '../../modules/settings/budget/presentation/screens/budget_list_screen.dart';
import '../../modules/settings/categories/presentation/screens/categories_screen.dart';
import '../../modules/settings/expense_type/presentation/screens/expense_type_screen.dart';
import '../../modules/tags/presentation/screens/tags_screen.dart';
import '../../modules/split_bills/presentation/screens/friend_split_detail_screen.dart';
import '../../modules/split_bills/presentation/screens/split_bill_detail_screen.dart';
import '../../modules/split_bills/presentation/screens/split_bills_screen.dart';
import '../../modules/subscription/presentation/screens/paywall_screen.dart';
import '../presentation/screens/web_view_screen.dart';
import 'app_shell.dart';

final router = GoRouter(
  initialLocation: rootRoute,
  routes: [
    GoRoute(path: rootRoute, builder: (context, state) => SplashScreen()),
    GoRoute(path: loginRoute, builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: consentRoute,
      builder: (context, state) => const ConsentScreen(),
    ),
    GoRoute(
      path: forceUpdateRoute,
      builder: (context, state) => const ForceUpdateScreen(),
    ),
    GoRoute(path: userNameRoute, builder: (context, state) => UserNameScreen()),
    GoRoute(
      path: contactsRoute,
      builder: (context, state) => ContactsScreen(),
      routes: [
        GoRoute(
          path: 'groups/:id',
          builder: (context, state) =>
              GroupDetailScreen(groupId: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: analysisRoute,
      builder: (context, state) => const AnalysisScreen(),
    ),
    GoRoute(
      path: budgetAnalyticsRoute,
      builder: (context, state) => const BudgetAnalyticsScreen(),
    ),
    GoRoute(
      path: categoryExpensesRoute,
      builder: (context, state) {
        final args = state.extra! as CategoryExpensesRouteArgs;
        return CategoryExpensesScreen(
          filter: args.filter,
          budget: args.budget,
        );
      },
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
      path: settingsExpenseTypeRoute,
      builder: (context, state) => const ExpenseTypeScreen(),
    ),
    GoRoute(
      path: settingsTagsRoute,
      builder: (context, state) => const TagsScreen(),
    ),
    GoRoute(
      path: budgetsRoute,
      builder: (context, state) => const BudgetListScreen(),
    ),
    GoRoute(
      path: paywallRoute,
      builder: (context, state) => const PaywallScreen(),
    ),
    GoRoute(
      path: recurringRoute,
      builder: (context, state) => const RecurringListScreen(),
    ),
    GoRoute(
      path: referralRoute,
      builder: (context, state) => const ReferralScreen(),
    ),
    GoRoute(
      path: referralOnboardingRoute,
      builder: (context, state) => const ReferralOnboardingScreen(),
    ),
    GoRoute(
      path: exportPdfRoute,
      builder: (context, state) => const ExportScreen(),
    ),
    GoRoute(
      path: profileRoute,
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: feedbackRoute,
      builder: (context, state) => const FeedbackScreen(),
    ),
    GoRoute(
      path: '/split-bills/friend/:friendId',
      builder: (context, state) =>
          FriendSplitDetailScreen(friendId: state.pathParameters['friendId']!),
    ),
    GoRoute(
      path: '/split-bills/:id',
      builder: (context, state) =>
          SplitBillDetailScreen(billId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/collabs/:id',
      builder: (context, state) =>
          CollabDetailScreen(collabId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'members',
          builder: (context, state) =>
              CollabMembersScreen(collabId: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: collabAnalyticsRoute,
      builder: (context, state) => CollabAnalysisScreen(
        collab: state.extra! as CollabModel,
      ),
    ),
    GoRoute(
      path: privacyPolicyRoute,
      builder: (context, state) => const WebViewScreen(
        title: 'Privacy Policy',
        url:
            'https://leean912.github.io/jomspendz-privacy-policy/privacy-policy.html',
      ),
    ),
    GoRoute(
      path: recurringExpenseFormRoute,
      builder: (context, state) => RecurringExpenseFormScreen(
        existing: state.extra as RecurringExpenseModel?,
      ),
    ),
    GoRoute(
      path: recurringSplitBillFormRoute,
      builder: (context, state) => RecurringSplitBillFormScreen(
        existing: state.extra as RecurringSplitBillModel?,
      ),
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
