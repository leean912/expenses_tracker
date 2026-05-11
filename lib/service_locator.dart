import 'package:jomspendz/core/config/env.dart';
import 'package:jomspendz/modules/subscription/data/services/revenue_cat_payment_service.dart';
import 'package:jomspendz/modules/subscription/domain/payment_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;
final env = Env();
final PaymentService paymentService = RevenueCatPaymentService();
