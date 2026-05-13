import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current required privacy policy version fetched from Supabase app_config.
/// Set by AuthNotifier._bootstrap() before any auth state fires.
final currentPolicyVersionProvider = StateProvider<int>((ref) => 1);

/// Minimum app version required to use the app, e.g. "1.2.0".
/// Set by AuthNotifier._bootstrap(). Empty string means no minimum enforced.
final minAppVersionProvider = StateProvider<String>((ref) => '');
