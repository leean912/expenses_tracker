enum ExpenseType {
  expense,
  income;

  String toValue() => name;

  static ExpenseType fromValue(String value) =>
      ExpenseType.values.firstWhere((e) => e.name == value);
}

enum ExpenseSource {
  manual,
  settlement,
  splitPayer,
  recurring,
  recurringSplit;

  String toValue() {
    switch (this) {
      case ExpenseSource.manual:
        return 'manual';
      case ExpenseSource.settlement:
        return 'settlement';
      case ExpenseSource.splitPayer:
        return 'split_payer';
      case ExpenseSource.recurring:
        return 'recurring';
      case ExpenseSource.recurringSplit:
        return 'recurring_split';
    }
  }

  static ExpenseSource fromValue(String value) {
    switch (value) {
      case 'manual':
        return ExpenseSource.manual;
      case 'settlement':
        return ExpenseSource.settlement;
      case 'split_payer':
        return ExpenseSource.splitPayer;
      case 'recurring':
        return ExpenseSource.recurring;
      case 'recurring_split':
        return ExpenseSource.recurringSplit;
      default:
        return ExpenseSource.manual;
    }
  }
}
