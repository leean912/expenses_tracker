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
    this.actualAmountCents,
    this.conversionRate,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.note,
    required this.expenseDate,
    required this.ownerDisplayName,
    this.ownerUsername,
    this.ownerAvatarUrl,
    this.isIncome = false,
    this.isSplitBill = false,
    this.hasReceipt = false,
    this.accountName,
    this.splitBillId,
  });

  final String id;
  final String userId;
  final int amountCents;
  final String currency;
  final int homeAmountCents;
  final String homeCurrency;
  final int? actualAmountCents;
  final double? conversionRate;
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColor;
  final String? note;
  final DateTime expenseDate;
  final String ownerDisplayName;
  final String? ownerUsername;
  final String? ownerAvatarUrl;
  final bool isIncome;
  final bool isSplitBill;
  final bool hasReceipt;
  final String? accountName;
  final String? splitBillId;

  bool get hasActualDifference =>
      !isIncome &&
      actualAmountCents != null &&
      actualAmountCents != homeAmountCents;

  factory CollabExpense.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'] as Map<String, dynamic>? ?? {};
    final category = json['category'] as Map<String, dynamic>?;
    final account = json['account'] as Map<String, dynamic>?;
    final source = json['source'] as String? ?? 'manual';
    return CollabExpense(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      amountCents: json['amount_cents'] as int,
      currency: json['currency'] as String,
      homeAmountCents: json['home_amount_cents'] as int? ?? 0,
      homeCurrency: json['home_currency'] as String? ?? '',
      actualAmountCents: json['actual_amount_cents'] as int?,
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
      isIncome: json['type'] == 'income',
      isSplitBill: source == 'split_payer' || source == 'settlement',
      hasReceipt: (json['receipt_url'] as String?)?.isNotEmpty == true,
      accountName: account?['name'] as String?,
      splitBillId: json['source_split_bill_id'] as String?,
    );
  }
}

class CollabExpensesState {
  const CollabExpensesState({
    required this.expenses,
    required this.hasMore,
  });

  final List<CollabExpense> expenses;

  /// True when more pages exist and [fetchMore] can be called.
  final bool hasMore;
}

class CollabExpensesNotifier
    extends AutoDisposeFamilyAsyncNotifier<CollabExpensesState, String> {
  static const _pageSize = 30;

  var _page = 0;
  var _hasMore = true;
  var _isFetchingMore = false;
  final _items = <CollabExpense>[];

  @override
  Future<CollabExpensesState> build(String collabId) async {
    _page = 0;
    _hasMore = true;
    _isFetchingMore = false;
    _items.clear();
    return _fetchPage(collabId);
  }

  Future<CollabExpensesState> _fetchPage(String collabId) async {
    final from = _page * _pageSize;

    final rows = await supabase
        .from('expenses')
        .select(
          'id, user_id, type, source, source_split_bill_id, amount_cents, '
          'currency, home_amount_cents, actual_amount_cents, home_currency, '
          'conversion_rate, note, expense_date, receipt_url, '
          'owner:profiles!user_id(id, username, display_name, avatar_url), '
          'category:categories(name, icon, color), account:accounts(name)',
        )
        .eq('collab_id', collabId)
        .isFilter('deleted_at', null)
        .order('expense_date', ascending: false)
        .order('created_at', ascending: false)
        .range(from, from + _pageSize - 1) as List<dynamic>;

    _hasMore = rows.length == _pageSize;
    _items.addAll(
      rows.map((r) => CollabExpense.fromJson(r as Map<String, dynamic>)),
    );
    _page++;
    return CollabExpensesState(
      expenses: List.unmodifiable(_items),
      hasMore: _hasMore,
    );
  }

  /// Removes a single expense from the local list without re-fetching.
  void removeExpense(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    _items.removeWhere((e) => e.id == id);
    state = AsyncData(CollabExpensesState(
      expenses: List.unmodifiable(_items),
      hasMore: _hasMore,
    ));
  }

  /// Fetches the next page and appends to the existing list.
  /// Safe to call multiple times — guarded by [_isFetchingMore].
  Future<void> fetchMore() async {
    if (!_hasMore || _isFetchingMore || state.isLoading) return;
    _isFetchingMore = true;
    try {
      final next = await _fetchPage(arg);
      state = AsyncData(next);
    } catch (_) {
      // Keep existing data on pagination error.
    } finally {
      _isFetchingMore = false;
    }
  }

  Future<void> refresh() async {
    _page = 0;
    _hasMore = true;
    _isFetchingMore = false;
    _items.clear();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPage(arg));
  }
}

final collabExpensesProvider = AsyncNotifierProvider.autoDispose
    .family<CollabExpensesNotifier, CollabExpensesState, String>(
  CollabExpensesNotifier.new,
);
