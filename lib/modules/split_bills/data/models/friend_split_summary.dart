import '../../providers/split_bills_provider.dart';
import 'my_share_item.dart';
import 'profile_summary.dart';
import 'split_bill_model.dart';

class FriendSplitSummary {
  const FriendSplitSummary({
    required this.friend,
    required this.billsIPaid,
    required this.billsFriendPaid,
  });

  final ProfileSummary friend;

  /// Bills where I paid and this friend is a share participant.
  final List<SplitBillModel> billsIPaid;

  /// Bills this friend paid and I am a share participant.
  final List<MyShareItem> billsFriendPaid;

  int get pendingBillsIPaid => billsIPaid
      .where(
        (b) => b.shares.any((s) => s.userId == friend.id && s.isPending),
      )
      .length;

  int get pendingBillsFriendPaid =>
      billsFriendPaid.where((item) => item.share.isPending).length;

  int get totalPendingBills => pendingBillsIPaid + pendingBillsFriendPaid;
  int get totalBills => billsIPaid.length + billsFriendPaid.length;

  static List<FriendSplitSummary> fromData(
    SplitBillsData data,
    String currentUserId,
  ) {
    final profiles = <String, ProfileSummary>{};
    final paidByMe = <String, List<SplitBillModel>>{};
    final paidByFriend = <String, List<MyShareItem>>{};

    for (final bill in data.myBills) {
      for (final share in bill.shares) {
        if (share.userId == currentUserId || share.user == null) continue;
        final fid = share.user!.id;
        profiles[fid] ??= share.user!;
        (paidByMe[fid] ??= []).add(bill);
      }
    }

    for (final item in data.myShares) {
      if (item.payer == null) continue;
      final fid = item.payer!.id;
      profiles[fid] ??= item.payer!;
      (paidByFriend[fid] ??= []).add(item);
    }

    return profiles.keys
        .map(
          (fid) => FriendSplitSummary(
            friend: profiles[fid]!,
            billsIPaid: paidByMe[fid] ?? [],
            billsFriendPaid: paidByFriend[fid] ?? [],
          ),
        )
        .toList()
      ..sort((a, b) => b.totalPendingBills.compareTo(a.totalPendingBills));
  }
}
