import 'book_documents.dart';
import 'local_import_batch.dart';

class LocalScanResult {
  const LocalScanResult({
    required this.report,
    required this.total,
    required this.unchanged,
    this.warnings = const [],
    this.pending = 0,
  });
  final LocalImportReport report;

  /// Matching books found in the folder, including ones already imported.
  final int total, unchanged;

  /// New or changed books still waiting to be imported.
  final int pending;
  final List<String> warnings;

  String get summary {
    if (total == 0) return '文件夹中没有找到可导入的书籍';
    final imported = report.added + report.existing;
    if (imported == 0 && report.failures.isEmpty) {
      return pending == 0 ? '没有新书，书库已是最新' : '发现 $pending 本新书';
    }
    return [
      '扫描完成',
      report.summary,
      if (pending > 0) '还有 $pending 本未导入',
    ].join('，');
  }
}

/// Imports the chosen scan tokens one at a time. A book is marked as seen
/// only after it imports cleanly, so a failed file is offered again next scan.
Future<LocalScanResult> scanLocalBooks({
  required BookDocuments documents,
  required BookScanSnapshot snapshot,
  required Set<String> selectedTokens,
  required bool linkText,
  required Future<LocalImportReport> Function(BookDocumentSelection source)
  importSource,
  required bool Function() current,
  void Function(int done, int total)? onProgress,
}) async {
  final chosen = [
    for (final book in snapshot.books)
      if (selectedTokens.contains(book.token)) book,
  ];
  var report = const LocalImportReport(bookIds: [], added: 0, existing: 0);
  var done = 0;
  try {
    for (final book in chosen) {
      if (!current()) break;
      try {
        final source = linkText
            ? await documents.linkScanBook(book.token)
            : await documents.stageScanBook(book.token);
        final imported = await importSource(source);
        report = report.merge(imported);
        if (imported.failures.isEmpty && imported.bookIds.isNotEmpty) {
          await documents.markScanBook(book.token);
        }
      } catch (error) {
        report = report.merge(
          LocalImportReport(
            bookIds: const [],
            added: 0,
            existing: 0,
            failures: [
              (name: book.name, message: localImportFailureMessage(error)),
            ],
          ),
        );
      }
      onProgress?.call(++done, chosen.length);
    }
  } finally {
    await documents.finishBookScan();
  }
  return LocalScanResult(
    report: report,
    total: snapshot.total,
    unchanged: snapshot.unchanged,
    warnings: snapshot.warnings,
    pending: snapshot.books.length - done,
  );
}
