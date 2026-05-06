import '../data/models/subscription_info.dart';

enum AppPurchaseResult { purchased, restored, cancelled }

abstract class PaymentService {
  Future<void> initialize();
  Future<void> identify(String userId);
  Future<void> logout();
  Future<SubscriptionInfo> getSubscriptionInfo();
  Stream<SubscriptionInfo> get customerInfoStream;
  Future<AppPurchaseResult> presentPaywall();
  Future<SubscriptionInfo> restorePurchases();
  Future<void> presentCustomerCenter();
}
