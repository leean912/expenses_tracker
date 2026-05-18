import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

import '../../../service_locator.dart';
import '../../expenses/data/models/account_model.dart';
import '../../expenses/data/models/category_model.dart';

enum ExportTransactionType { all, expensesOnly, incomeOnly }

enum ExportSortOrder { dateDesc, dateAsc, amountDesc }

enum ExportFormat { pdf, excel }

class ExportPdfFilter {
  const ExportPdfFilter({
    required this.startDate,
    required this.endDate,
    required this.fileName,
    this.transactionType = ExportTransactionType.all,
    this.selectedCategoryIds,
    this.selectedAccountIds,
    this.includeSplitBill = true,
    this.includeRecurring = true,
    this.sortOrder = ExportSortOrder.dateDesc,
    this.exportFormat = ExportFormat.pdf,
    this.includeReceipts = false,
  });

  final DateTime startDate;
  final DateTime endDate;
  final String fileName;
  final ExportTransactionType transactionType;
  final Set<String>? selectedCategoryIds;
  final Set<String>? selectedAccountIds;
  final bool includeSplitBill;
  final bool includeRecurring;
  final ExportSortOrder sortOrder;
  final ExportFormat exportFormat;
  final bool includeReceipts;

  ExportPdfFilter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? fileName,
    ExportTransactionType? transactionType,
    Set<String>? selectedCategoryIds,
    bool clearCategories = false,
    Set<String>? selectedAccountIds,
    bool clearAccounts = false,
    bool? includeSplitBill,
    bool? includeRecurring,
    ExportSortOrder? sortOrder,
    ExportFormat? exportFormat,
    bool? includeReceipts,
  }) {
    return ExportPdfFilter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      fileName: fileName ?? this.fileName,
      transactionType: transactionType ?? this.transactionType,
      selectedCategoryIds:
          clearCategories ? null : (selectedCategoryIds ?? this.selectedCategoryIds),
      selectedAccountIds:
          clearAccounts ? null : (selectedAccountIds ?? this.selectedAccountIds),
      includeSplitBill: includeSplitBill ?? this.includeSplitBill,
      includeRecurring: includeRecurring ?? this.includeRecurring,
      sortOrder: sortOrder ?? this.sortOrder,
      exportFormat: exportFormat ?? this.exportFormat,
      includeReceipts: includeReceipts ?? this.includeReceipts,
    );
  }
}

class ExportPdfNotifier extends Notifier<ExportPdfFilter> {
  @override
  ExportPdfFilter build() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final defaultName = 'jomspendz_${DateFormat('yyyyMMdd_HHmmss').format(now)}';
    return ExportPdfFilter(
      startDate: monthStart,
      endDate: now,
      fileName: defaultName,
    );
  }

  void setDateRange(DateTime start, DateTime end) =>
      state = state.copyWith(startDate: start, endDate: end);

  void setFileName(String name) => state = state.copyWith(fileName: name);

  void setTransactionType(ExportTransactionType type) =>
      state = state.copyWith(transactionType: type);

  void toggleCategory(String id) {
    final current = Set<String>.from(state.selectedCategoryIds ?? {});
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    state = state.copyWith(selectedCategoryIds: current);
  }

  void selectAllCategories() => state = state.copyWith(clearCategories: true);

  void toggleAccount(String id) {
    final current = Set<String>.from(state.selectedAccountIds ?? {});
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    state = state.copyWith(selectedAccountIds: current);
  }

  void selectAllAccounts() => state = state.copyWith(clearAccounts: true);

  void setIncludeSplitBill(bool v) => state = state.copyWith(includeSplitBill: v);

  void setIncludeRecurring(bool v) => state = state.copyWith(includeRecurring: v);

  void setSortOrder(ExportSortOrder order) => state = state.copyWith(sortOrder: order);

  void setExportFormat(ExportFormat format) => state = state.copyWith(exportFormat: format);

  void setIncludeReceipts(bool v) => state = state.copyWith(includeReceipts: v);

  static const _exportPageSize = 500;

  Future<List<Map<String, dynamic>>> _fetchAllExportRows(
    ExportPdfFilter filter,
    String userId,
    String startStr,
    String endStr,
  ) async {
    final all = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      var query = supabase
          .from('expenses')
          .select(
            'id, type, amount_cents, currency, home_amount_cents, home_currency, '
            'expense_date, note, category_id, account_id, source, receipt_url',
          )
          .isFilter('deleted_at', null)
          .isFilter('archived_at', null)
          .eq('user_id', userId)
          .gte('expense_date', startStr)
          .lte('expense_date', endStr);

      if (filter.transactionType == ExportTransactionType.expensesOnly) {
        query = query.eq('type', 'expense');
      } else if (filter.transactionType == ExportTransactionType.incomeOnly) {
        query = query.eq('type', 'income');
      }
      if (!filter.includeSplitBill) {
        query = query.isFilter('source_split_bill_id', null);
      }
      if (!filter.includeRecurring) {
        query = query.isFilter('source_recurring_expense_id', null);
      }

      final page = List<Map<String, dynamic>>.from(
        (await query.range(from, from + _exportPageSize - 1)) as List,
      );
      all.addAll(page);
      if (page.length < _exportPageSize) break;
      from += _exportPageSize;
    }
    return all;
  }

  Future<void> export(
    List<CategoryModel> allCategories,
    List<AccountModel> allAccounts,
  ) async {
    final filter = state;
    final userId = supabase.auth.currentUser!.id;

    final startStr = DateFormat('yyyy-MM-dd').format(filter.startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(filter.endDate);

    final rows = await _fetchAllExportRows(filter, userId, startStr, endStr);

    switch (filter.sortOrder) {
      case ExportSortOrder.dateDesc:
        rows.sort((a, b) =>
            (b['expense_date'] as String).compareTo(a['expense_date'] as String));
      case ExportSortOrder.dateAsc:
        rows.sort((a, b) =>
            (a['expense_date'] as String).compareTo(b['expense_date'] as String));
      case ExportSortOrder.amountDesc:
        rows.sort((a, b) => (b['home_amount_cents'] as num)
            .compareTo(a['home_amount_cents'] as num));
    }

    final catMap = {for (final c in allCategories) c.id: c};
    final accMap = {for (final a in allAccounts) a.id: a};

    final filtered = rows.where((row) {
      final catId = row['category_id'] as String?;
      final accId = row['account_id'] as String?;
      final catOk = filter.selectedCategoryIds == null ||
          (catId != null && filter.selectedCategoryIds!.contains(catId));
      final accOk = filter.selectedAccountIds == null ||
          (accId != null && filter.selectedAccountIds!.contains(accId));
      return catOk && accOk;
    }).toList();

    if (filter.exportFormat == ExportFormat.excel) {
      await _exportExcel(filter, filtered, catMap, accMap);
    } else {
      await _exportPdf(filter, filtered, catMap, accMap);
    }
  }

  // ── PDF ────────────────────────────────────────────────────────────────────

  Future<void> _exportPdf(
    ExportPdfFilter filter,
    List<Map<String, dynamic>> filtered,
    Map<String, CategoryModel> catMap,
    Map<String, AccountModel> accMap,
  ) async {
    final amountFmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('d MMM yyyy');

    final Map<String, Uint8List> receiptImages = {};
    if (filter.includeReceipts) {
      for (final row in filtered) {
        final url = row['receipt_url'] as String?;
        if (url != null) {
          final bytes = await _fetchBytes(url);
          if (bytes != null) receiptImages[row['id'] as String] = bytes;
        }
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Spendz Export',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${dateFmt.format(filter.startDate)} – ${dateFmt.format(filter.endDate)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(),
          ],
        ),
        build: (_) => [
          _buildPdfTable(
            filtered,
            catMap,
            accMap,
            receiptImages,
            amountFmt,
            dateFmt,
            filter.includeReceipts,
          ),
          pw.SizedBox(height: 16),
          _buildSummary(filtered, amountFmt),
        ],
      ),
    );

    final name =
        filter.fileName.trim().isEmpty ? 'spendz_export' : filter.fileName.trim();
    await Printing.sharePdf(bytes: await pdf.save(), filename: '$name.pdf');
  }

  pw.Widget _buildPdfTable(
    List<Map<String, dynamic>> filtered,
    Map<String, CategoryModel> catMap,
    Map<String, AccountModel> accMap,
    Map<String, Uint8List> receiptImages,
    NumberFormat amountFmt,
    DateFormat dateFmt,
    bool includeReceipts,
  ) {
    const cellPad = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5);

    pw.Widget headerCell(String text, {pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          padding: cellPad,
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          alignment: align,
          child: pw.Text(
            text,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        );

    pw.Widget dataCell(String text, {pw.Alignment align = pw.Alignment.centerLeft}) =>
        pw.Container(
          padding: cellPad,
          alignment: align,
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
        );

    final columnWidths = includeReceipts
        ? <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(2.2),
            4: const pw.FlexColumnWidth(1.6),
            5: const pw.FixedColumnWidth(72),
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(2.2),
            4: const pw.FlexColumnWidth(1.6),
          };

    final headerRow = pw.TableRow(children: [
      headerCell('Date'),
      headerCell('Category'),
      headerCell('Account'),
      headerCell('Note'),
      headerCell('Amount', align: pw.Alignment.centerRight),
      if (includeReceipts) headerCell('Receipt', align: pw.Alignment.center),
    ]);

    final dataRows = filtered.map((row) {
      final catId = row['category_id'] as String?;
      final accId = row['account_id'] as String?;
      final cat = catId != null ? catMap[catId] : null;
      final acc = accId != null ? accMap[accId] : null;
      final isIncome = row['type'] == 'income';
      final cents = (row['home_amount_cents'] as num).toInt();
      final currency = row['home_currency'] as String? ?? 'MYR';
      final amount = '${isIncome ? '+' : '-'}$currency ${amountFmt.format(cents / 100)}';
      final date = dateFmt.format(DateTime.parse(row['expense_date'] as String));
      final bytes = includeReceipts ? receiptImages[row['id'] as String] : null;

      return pw.TableRow(children: [
        dataCell(date),
        dataCell(cat?.name ?? '—'),
        dataCell(acc?.name ?? '—'),
        dataCell(row['note'] as String? ?? ''),
        dataCell(amount, align: pw.Alignment.centerRight),
        if (includeReceipts)
          pw.Container(
            padding: cellPad,
            alignment: pw.Alignment.center,
            child: bytes != null
                ? pw.ConstrainedBox(
                    constraints: const pw.BoxConstraints(maxHeight: 72, maxWidth: 72),
                    child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
                  )
                : pw.SizedBox(),
          ),
      ]);
    }).toList();

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [headerRow, ...dataRows],
    );
  }

  // ── Excel ──────────────────────────────────────────────────────────────────

  Future<void> _exportExcel(
    ExportPdfFilter filter,
    List<Map<String, dynamic>> filtered,
    Map<String, CategoryModel> catMap,
    Map<String, AccountModel> accMap,
  ) async {
    final dateFmt = DateFormat('d MMM yyyy');

    final workbook = xls.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Transactions';

    final headers = [
      'Date',
      'Type',
      'Category',
      'Account',
      'Note',
      'Currency',
      'Amount',
    ];

    // Header row
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle.bold = true;
    }

    // Data rows
    for (int i = 0; i < filtered.length; i++) {
      final row = filtered[i];
      final catId = row['category_id'] as String?;
      final accId = row['account_id'] as String?;
      final cat = catId != null ? catMap[catId] : null;
      final acc = accId != null ? accMap[accId] : null;
      final isIncome = row['type'] == 'income';
      final cents = (row['home_amount_cents'] as num).toInt();
      final currency = row['home_currency'] as String? ?? 'MYR';
      final amount = (isIncome ? 1.0 : -1.0) * cents / 100;
      final date = dateFmt.format(DateTime.parse(row['expense_date'] as String));
      final rowIndex = i + 2;

      sheet.getRangeByIndex(rowIndex, 1).setText(date);
      sheet.getRangeByIndex(rowIndex, 2).setText(isIncome ? 'Income' : 'Expense');
      sheet.getRangeByIndex(rowIndex, 3).setText(cat?.name ?? '');
      sheet.getRangeByIndex(rowIndex, 4).setText(acc?.name ?? '');
      sheet.getRangeByIndex(rowIndex, 5).setText(row['note'] as String? ?? '');
      sheet.getRangeByIndex(rowIndex, 6).setText(currency);
      sheet.getRangeByIndex(rowIndex, 7).setNumber(amount);

    }

    // Auto-fit columns
    for (int i = 1; i <= headers.length; i++) {
      sheet.autoFitColumn(i);
    }

    // Summary rows
    int totalExpense = 0;
    int totalIncome = 0;
    for (final row in filtered) {
      final cents = (row['home_amount_cents'] as num).toInt();
      if (row['type'] == 'income') {
        totalIncome += cents;
      } else {
        totalExpense += cents;
      }
    }
    final currency = filtered.isNotEmpty
        ? (filtered.first['home_currency'] as String? ?? 'MYR')
        : 'MYR';

    int summaryRow = filtered.length + 3;

    final countCell = sheet.getRangeByIndex(summaryRow, 6);
    countCell.setText('Total Transactions:');
    countCell.cellStyle.bold = true;
    final countVal = sheet.getRangeByIndex(summaryRow, 7);
    countVal.setNumber(filtered.length.toDouble());
    countVal.cellStyle.bold = true;
    summaryRow++;

    if (totalIncome > 0) {
      final label = sheet.getRangeByIndex(summaryRow, 6);
      label.setText('Total Income ($currency):');
      label.cellStyle.bold = true;
      final val = sheet.getRangeByIndex(summaryRow, 7);
      val.setNumber(totalIncome / 100);
      val.cellStyle.bold = true;
      summaryRow++;
    }

    if (totalExpense > 0) {
      final label = sheet.getRangeByIndex(summaryRow, 6);
      label.setText('Total Expenses ($currency):');
      label.cellStyle.bold = true;
      final val = sheet.getRangeByIndex(summaryRow, 7);
      val.setNumber(-totalExpense / 100);
      val.cellStyle.bold = true;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final name =
        filter.fileName.trim().isEmpty ? 'spendz_export' : filter.fileName.trim();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.xlsx');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<Uint8List?> _fetchBytes(String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      client.close();
      return builder.takeBytes();
    } catch (_) {
      return null;
    }
  }

  pw.Widget _buildSummary(List rows, NumberFormat fmt) {
    int totalExpense = 0;
    int totalIncome = 0;
    for (final row in rows) {
      final cents = (row['home_amount_cents'] as num).toInt();
      if (row['type'] == 'income') {
        totalIncome += cents;
      } else {
        totalExpense += cents;
      }
    }
    final currency =
        rows.isNotEmpty ? (rows.first['home_currency'] as String? ?? 'MYR') : 'MYR';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                '${rows.length} transaction${rows.length == 1 ? '' : 's'}',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
              pw.SizedBox(height: 4),
              if (totalIncome > 0)
                pw.Text(
                  'Income: +$currency ${fmt.format(totalIncome / 100)}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.green700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              if (totalExpense > 0)
                pw.Text(
                  'Expenses: -$currency ${fmt.format(totalExpense / 100)}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.red700,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

final exportPdfProvider =
    NotifierProvider<ExportPdfNotifier, ExportPdfFilter>(ExportPdfNotifier.new);
