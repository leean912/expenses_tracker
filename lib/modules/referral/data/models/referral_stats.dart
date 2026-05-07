class ReferralStats {
  const ReferralStats({
    required this.referralCode,
    required this.totalReferrals,
    required this.hasUsedReferral,
    this.bonusExpiresAt,
  });

  final String referralCode;
  final int totalReferrals;
  final bool hasUsedReferral;
  final DateTime? bonusExpiresAt;

  int get totalDaysEarned => totalReferrals * 3;

  bool get isBonusActive =>
      bonusExpiresAt != null && bonusExpiresAt!.isAfter(DateTime.now());
}
