import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/my_share_item.dart';
import '../data/models/profile_summary.dart';
import '../data/models/split_bill_model.dart';
import '../data/models/split_share_model.dart';

// ── Bills (I Paid) ────────────────────────────────────────────────────────────

class MyBillsState {
  const MyBillsState({required this.items, required this.hasMore});
  final List<SplitBillModel> items;
  final bool hasMore;
}

class MyBillsNotifier extends AsyncNotifier<MyBillsState> {
  static const _pageSize = 30;

  var _page = 0;
  var _hasMore = true;
  var _isFetchingMore = false;
  final _items = <SplitBillModel>[];

  @override
  Future<MyBillsState> build() async {
    ref.watch(currentUserIdProvider);
    _page = 0;
    _hasMore = true;
    _isFetchingMore = false;
    _items.clear();
    return _fetchPage();
  }

  Future<MyBillsState> _fetchPage() async {
    final userId = supabase.auth.currentUser!.id;
    final from = _page * _pageSize;

    final raw = await supabase
        .from('split_bills')
        .select(
          '*, shares:split_bill_shares(*, user:profiles(id, username, display_name, avatar_url)), '
          'payer:profiles!paid_by(id, username, display_name, avatar_url)',
        )
        .eq('created_by', userId)
        .isFilter('deleted_at', null)
        .order('expense_date', ascending: false)
        .range(from, from + _pageSize - 1) as List<dynamic>;

    _hasMore = raw.length == _pageSize;
    _items.addAll(
      raw.map((r) => SplitBillModel.fromJson(r as Map<String, dynamic>)),
    );
    _page++;
    return MyBillsState(items: List.unmodifiable(_items), hasMore: _hasMore);
  }

  Future<void> fetchMore() async {
    if (!_hasMore || _isFetchingMore || state.isLoading) return;
    _isFetchingMore = true;
    try {
      state = AsyncData(await _fetchPage());
    } catch (_) {
    } finally {
      _isFetchingMore = false;
    }
  }

  Future<String?> deleteSplitBill(
    String billId, {
    bool deleteRelatedExpenses = false,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final userId = supabase.auth.currentUser!.id;

      if (deleteRelatedExpenses) {
        await supabase
            .from('expenses')
            .update({'deleted_at': now})
            .eq('source_split_bill_id', billId)
            .eq('user_id', userId)
            .isFilter('deleted_at', null);

        final sharesRaw = await supabase
            .from('split_bill_shares')
            .select('id')
            .eq('split_bill_id', billId);
        final shareIds =
            (sharesRaw as List<dynamic>).map((r) => r['id'] as String).toList();

        if (shareIds.isNotEmpty) {
          final settlementsRaw = await supabase
              .from('settlements')
              .select('id')
              .inFilter('split_bill_share_id', shareIds);
          final settlementIds = (settlementsRaw as List<dynamic>)
              .map((r) => r['id'] as String)
              .toList();

          if (settlementIds.isNotEmpty) {
            await supabase
                .from('expenses')
                .update({'deleted_at': now})
                .inFilter('source_settlement_id', settlementIds)
                .eq('user_id', userId)
                .isFilter('deleted_at', null);
          }
        }
      }

      await supabase
          .from('split_bills')
          .update({'deleted_at': now})
          .eq('id', billId);

      _items.removeWhere((b) => b.id == billId);
      state = AsyncData(
        MyBillsState(items: List.unmodifiable(_items), hasMore: _hasMore),
      );
      return null;
    } catch (e) {
      return 'Failed to delete. Please try again.';
    }
  }

  Future<String?> creatorMarkSharePaid(String shareId) async {
    try {
      await supabase
          .rpc('creator_mark_share_paid', params: {'p_share_id': shareId});
      ref.invalidateSelf();
      return null;
    } catch (e) {
      return 'Failed to mark as paid. Please try again.';
    }
  }

  Future<String?> updateShareAmount({
    required String shareId,
    required int newCents,
  }) async {
    try {
      await supabase
          .from('split_bill_shares')
          .update({
            'share_cents': newCents,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', shareId);
      ref.invalidateSelf();
      return null;
    } catch (e) {
      return 'Failed to update amount. Please try again.';
    }
  }
}

final myBillsProvider =
    AsyncNotifierProvider<MyBillsNotifier, MyBillsState>(MyBillsNotifier.new);

// ── Shares (I Owe) ────────────────────────────────────────────────────────────

class MySharesState {
  const MySharesState({required this.items, required this.hasMore});
  final List<MyShareItem> items;
  final bool hasMore;
}

class MySharesNotifier extends AsyncNotifier<MySharesState> {
  static const _pageSize = 30;

  var _page = 0;
  var _hasMore = true;
  var _isFetchingMore = false;
  final _items = <MyShareItem>[];

  @override
  Future<MySharesState> build() async {
    ref.watch(currentUserIdProvider);
    _page = 0;
    _hasMore = true;
    _isFetchingMore = false;
    _items.clear();
    return _fetchPage();
  }

  Future<MySharesState> _fetchPage() async {
    final userId = supabase.auth.currentUser!.id;
    final from = _page * _pageSize;

    final raw = await supabase
        .from('split_bill_shares')
        .select(
          '*, bill:split_bills!inner(id, note, total_amount_cents, currency, '
          'expense_date, paid_by, deleted_at, '
          'payer:profiles!paid_by(id, username, display_name, avatar_url))',
        )
        .eq('user_id', userId)
        .isFilter('archived_at', null)
        .order('created_at', ascending: false)
        .range(from, from + _pageSize - 1) as List<dynamic>;

    _hasMore = raw.length == _pageSize;

    final page = raw
        .map((r) => r as Map<String, dynamic>)
        .where((r) {
          final bill = r['bill'] as Map<String, dynamic>?;
          return bill != null &&
              bill['paid_by'] != userId &&
              bill['deleted_at'] == null;
        })
        .map((r) {
          final billData = r['bill'] as Map<String, dynamic>;
          final shareData = Map<String, dynamic>.from(r)..remove('bill');
          shareData['split_bill_id'] = billData['id'];
          return MyShareItem(
            share: SplitShareModel.fromJson(shareData),
            billId: billData['id'] as String,
            billNote: billData['note'] as String? ?? '',
            billTotalCents: (billData['total_amount_cents'] as num).toInt(),
            currency: billData['currency'] as String? ?? 'MYR',
            expenseDate: DateTime.parse(billData['expense_date'] as String),
            payer: billData['payer'] != null
                ? ProfileSummary.fromJson(
                    billData['payer'] as Map<String, dynamic>,
                  )
                : null,
          );
        })
        .toList();

    _items.addAll(page);
    _page++;
    return MySharesState(items: List.unmodifiable(_items), hasMore: _hasMore);
  }

  Future<void> fetchMore() async {
    if (!_hasMore || _isFetchingMore || state.isLoading) return;
    _isFetchingMore = true;
    try {
      state = AsyncData(await _fetchPage());
    } catch (_) {
    } finally {
      _isFetchingMore = false;
    }
  }

  Future<String?> settleShare({
    required String shareId,
    required String categoryId,
    required String accountId,
  }) async {
    try {
      await supabase.rpc('settle_split_share', params: {
        'p_share_id': shareId,
        'p_category_id': categoryId,
        'p_account_id': accountId,
      });
      ref.invalidateSelf();
      ref.invalidate(myBillsProvider);
      return null;
    } catch (e) {
      return 'Failed to settle. Please try again.';
    }
  }
}

final mySharesProvider =
    AsyncNotifierProvider<MySharesNotifier, MySharesState>(
  MySharesNotifier.new,
);
