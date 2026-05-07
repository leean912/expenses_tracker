class ReferralStats {
  const ReferralStats({
    required this.referralCode,
    required this.totalReferrals,
    required this.hasUsedReferral,
    required this.referralsUntilNext,
    this.bonusExpiresAt,
  });

  final String referralCode;
  final int totalReferrals;
  final bool hasUsedReferral;
  final int referralsUntilNext;
  final DateTime? bonusExpiresAt;

  int get totalDaysEarned => (totalReferrals ~/ 5) * 7;
  int get completedMilestones => totalReferrals ~/ 5;
  int get progressInCurrentMilestone => totalReferrals % 5;

  bool get isBonusActive =>
      bonusExpiresAt != null && bonusExpiresAt!.isAfter(DateTime.now());
}
