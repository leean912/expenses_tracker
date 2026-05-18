import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/preferences_service.dart';

enum ExpenseType { total, actual }

class ExpenseTypeNotifier extends AsyncNotifier<ExpenseType> {
  @override
  Future<ExpenseType> build() async {
    final stored = await PreferencesService.getExpenseType();
    return stored == 'actual' ? ExpenseType.actual : ExpenseType.total;
  }

  Future<void> setType(ExpenseType type) async {
    await PreferencesService.setExpenseType(type.name);
    state = AsyncData(type);
  }
}

final expenseTypeProvider =
    AsyncNotifierProvider<ExpenseTypeNotifier, ExpenseType>(
  ExpenseTypeNotifier.new,
);
