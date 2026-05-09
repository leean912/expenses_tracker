import 'package:envied/envied.dart';
import 'package:flutter/foundation.dart';

part 'env.g.dart';

@Envied(path: 'env/.env.prod', name: 'ProductionEnv', obfuscate: true)
@Envied(path: 'env/.env.dev', name: 'DebugEnv', obfuscate: true)
final class Env {
  factory Env() => _instance;

  static final Env _instance = switch (kDebugMode) {
    true => _DebugEnv(),
    false => _ProductionEnv(),
  };

  @EnviedField(varName: 'SUPABASE_API_URL')
  final String supabaseApiUrl = _instance.supabaseApiUrl;

  @EnviedField(varName: 'SUPABASE_API_KEY')
  final String supabaseApiKey = _instance.supabaseApiKey;

  @EnviedField(varName: 'GOOGLE_LOGIN_WEB_CLIENT_ID')
  final String googleLoginWebClientId = _instance.googleLoginWebClientId;

  @EnviedField(varName: 'GOOGLE_LOGIN_IOS_CLIENT_ID')
  final String googleLoginIosClientId = _instance.googleLoginIosClientId;

  @EnviedField(varName: 'REVENUECAT_API_KEY')
  final String revenueCatApiKey = _instance.revenueCatApiKey;
}
