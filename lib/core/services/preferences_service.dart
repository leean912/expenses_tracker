import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const _expenseTypeKey = 'expense_type_preference';

  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<String?> getExpenseType() => getString(_expenseTypeKey);

  static Future<void> setExpenseType(String value) =>
      setString(_expenseTypeKey, value);
}
