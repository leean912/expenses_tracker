import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';

class CollabExpense {
  const CollabExpense({
    required this.id,
    required this.userId,
    required this.amountCents,
    required this.currency,
    required this.homeAmountCents,
    required this.homeCurrency,
    this.conversionRate,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.note,
    required this.expenseDate,
    required this.ownerDisplayName,
    this.ownerUsername,
    this.ownerAvatarUrl,
  });

  final String id;
  final String userId;
  final int amountCents;
  final String currency;
  final int homeAmountCents;
  final String homeCurrency;
  final double? conversionRate;
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColor;
  final String? note;
  final DateTime expenseDate;
  final String ownerDisplayName;
  final String? ownerUsername;
  final String? ownerAvatarUrl;

  factory CollabExpense.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'] as Map<String, dynamic>? ?? {};
    final category = json['category'] as Map<String, dynamic>?;
    return CollabExpense(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      amountCents: json['amount_cents'] as int,
      currency: json['currency'] as String,
      homeAmountCents: json['home_amount_cents'] as int? ?? 0,
      homeCurrency: json['home_currency'] as String? ?? '',
      conversionRate: json['conversion_rate'] != null
          ? double.tryParse(json['conversion_rate'].toString())
          : null,
      categoryName: category?['name'] as String?,
      categoryIcon: category?['icon'] as String?,
      categoryColor: category?['color'] as String?,
      note: json['note'] as String?,
      expenseDate: DateTime.parse(json['expense_date'] as String),
      ownerDisplayName: owner['display_name'] as String? ?? '',
      ownerUsername: owner['username'] as String?,
      ownerAvatarUrl: owner['avatar_url'] as String?,
    );
  }
}

class CollabExpensesState {
  const CollabExpensesState({
    this.expenses = const [],
    this.totalHomeAmountCents = 0,
    this.isLoading = false,
    this.error,
  });

  final List<CollabExpense> expenses;
  final int totalHomeAmountCents;
  final bool isLoading;
  final String? error;
}

class CollabExpensesNotifier
    extends AutoDisposeFamilyAsyncNotifier<CollabExpensesState, String> {
  @override
  Future<CollabExpensesState> build(String collabId) => _fetch(collabId);

  Future<CollabExpensesState> _fetch(String collabId) async {
    final rows = await supabase
        .from('expenses')
        .select(
          'id, user_id, amount_cents, currency, home_amount_cents, home_currency, conversion_rate, note, expense_date, owner:profiles!user_id(id, username, display_name, avatar_url), category:categories(name, icon, color)',
        )
        .eq('collab_id', collabId)
        .isFilter('deleted_at', null)
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false);

    final expenses = (rows as List)
        .map((r) => CollabExpense.fromJson(r as Map<String, dynamic>))
        .toList();

    final total = expenses.fold<int>(0, (sum, e) => sum + e.homeAmountCents);

    return CollabExpensesState(expenses: expenses, totalHomeAmountCents: total);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(arg));
  }
}

final collabExpensesProvider = AsyncNotifierProvider.autoDispose
    .family<CollabExpensesNotifier, CollabExpensesState, String>(
      CollabExpensesNotifier.new,
    );
