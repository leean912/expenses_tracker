import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../../service_locator.dart';
import '../../domain/payment_service.dart';
import '../models/subscription_info.dart';

class RevenueCatPaymentService implements PaymentService {
  final _iOSApiKey = env.revenueCatApiKey;
  final _androidApiKey = env.revenueCatApiKey;
  static const _entitlementKey = 'spendz Pro';

  final _customerInfoController =
      StreamController<SubscriptionInfo>.broadcast();

  @override
  Stream<SubscriptionInfo> get customerInfoStream =>
      _customerInfoController.stream;

  @override
  Future<void> initialize() async {
    if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
    final apiKey = Platform.isIOS ? _iOSApiKey : _androidApiKey;
    await Purchases.configure(PurchasesConfiguration(apiKey));
    Purchases.addCustomerInfoUpdateListener((info) {
      if (!_customerInfoController.isClosed) {
        _customerInfoController.add(_fromCustomerInfo(info));
      }
    });
  }

  @override
  Future<void> identify(String userId) async {
    await Purchases.logIn(userId);
  }

  @override
  Future<void> logout() async {
    await Purchases.logOut();
  }

  @override
  Future<SubscriptionInfo> getSubscriptionInfo() async {
    final info = await Purchases.getCustomerInfo();
    return _fromCustomerInfo(info);
  }

  @override
  Future<AppPurchaseResult> presentPaywall() async {
    final result = await RevenueCatUI.presentPaywall();
    return switch (result) {
      PaywallResult.purchased => AppPurchaseResult.purchased,
      PaywallResult.restored => AppPurchaseResult.restored,
      _ => AppPurchaseResult.cancelled,
    };
  }

  @override
  Future<SubscriptionInfo> restorePurchases() async {
    final info = await Purchases.restorePurchases();
    return _fromCustomerInfo(info);
  }

  @override
  Future<void> presentCustomerCenter() async {
    await RevenueCatUI.presentCustomerCenter();
  }

  SubscriptionInfo _fromCustomerInfo(CustomerInfo info) {
    final entitlement = info.entitlements.active[_entitlementKey];
    return SubscriptionInfo(
      isPremium: entitlement != null,
      expiresAt: entitlement?.expirationDate != null
          ? DateTime.tryParse(entitlement!.expirationDate!)
          : null,
    );
  }
}
