import 'dart:io';

import 'package:flutter/services.dart';

import 'book_documents.dart';
import 'catalog.dart';
import 'local_books.dart';

typedef LocalImportNotice = ({String name, String message});

class LocalImportReport {
  const LocalImportReport({
    required this.bookIds,
    required this.added,
    required this.existing,
    this.failures = const [],
    this.notices = const [],
  });
  final List<int> bookIds;
  final int added, existing;
  final List<LocalImportNotice> failures, notices;

  String get summary {
    final parts = [
      if (added > 0) '新增 $added 本',
      if (existing > 0) '$existing 本已在书库',
      if (failures.isNotEmpty) '${failures.length} 个文件未导入',
    ];
    return parts.isEmpty ? '没有可导入的书籍' : parts.join('，');
  }

  LocalImportReport merge(LocalImportReport other) => LocalImportReport(
    bookIds: {...bookIds, ...other.bookIds}.toList(),
    added: added + other.added,
    existing: existing + other.existing,
    failures: [...failures, ...other.failures],
    notices: [...notices, ...other.notices],
  );
}

String localImportFailureMessage(Object error) => switch (error) {
  FormatException e when e.message.isNotEmpty => e.message,
  PlatformException e when (e.message ?? '').isNotEmpty => e.message!,
  FileSystemException e when e.osError?.errorCode == 28 =>
    '存储空间不足，请清理空间后重新导入',
  FileSystemException _ => '无法读取或保存原书，请检查文件与存储空间',
  _ => '无法导入这本书，请重新选择原文件',
};

/// Stages, converts and imports each selection in order. One bad file becomes
/// a failure entry; the rest of the batch continues. ZIP archives and
/// converted formats expand to several prepared documents.
Future<LocalImportReport> importLocalDocuments({
  required List<BookDocumentSelection> selections,
  required BookDocuments documents,
  required LocalBookStore books,
  required Future<Novel> Function(String name, String path) importFile,
  required Future<Novel> Function(BookDocumentSelection selected)
  importSelection,
  bool releaseSources = false,
  void Function(List<BookDocumentSelection> pending)? onCleanupFailed,
  void Function(int done, int total)? onProgress,
}) async {
  final known = {for (final book in books.books) book.id};
  final ids = <int>[];
  final failures = <LocalImportNotice>[];
  var added = 0, existing = 0, done = 0;
  Future<void> release(List<BookDocumentSelection> items) async {
    if (items.isEmpty) return;
    try {
      await documents.releaseBooks(items);
    } catch (_) {
      onCleanupFailed?.call(items);
    }
  }

  for (final selection in selections) {
    final disposable = <BookDocumentSelection>[];
    try {
      if (selection.error case final error?) {
        failures.add((name: selection.name, message: error));
        continue;
      }
      final staged = await documents.stageForImport(selection);
      if (releaseSources && staged.path != null) disposable.add(staged);
      if (staged.error case final error?) {
        failures.add((name: staged.name, message: error));
        continue;
      }
      final prepared = await documents.prepareBook(staged);
      for (final item in prepared) {
        if (item.path != null && item.path != staged.path) {
          disposable.add(item);
        }
      }
      for (final item in prepared) {
        if (item.error case final error?) {
          failures.add((name: item.name, message: error));
          continue;
        }
        try {
          final book = await importSelection(item);
          if (!ids.contains(book.id)) ids.add(book.id);
          if (known.add(book.id)) {
            added++;
          } else {
            existing++;
          }
        } catch (error) {
          failures.add((name: item.name, message: localImportFailureMessage(error)));
        }
      }
    } catch (error) {
      failures.add((
        name: selection.name,
        message: localImportFailureMessage(error),
      ));
    } finally {
      await release(disposable);
      onProgress?.call(++done, selections.length);
    }
  }
  return LocalImportReport(
    bookIds: ids,
    added: added,
    existing: existing,
    failures: failures,
  );
}

class LocalImportGroup {
  const LocalImportGroup({
    required this.seed,
    required this.title,
    required this.volumes,
    this.targetId,
    this.needsTarget = false,
  });

  /// An imported original that represents the group in the review page.
  final int seed;
  final String title;
  final List<({int bookId, String title})> volumes;

  /// An existing series the new volumes would join.
  final int? targetId;

  /// Several existing series match, so the user picks one in the editor.
  final bool needsTarget;
}

/// Suggests series merges for freshly imported volumes. Only originals that
/// are not yet in a series are proposed; nothing merges without review.
List<LocalImportGroup> localImportGroups(
  LocalBookStore books,
  List<int> importedIds,
) {
  final groups = <LocalImportGroup>[];
  final claimed = <int>{};
  for (final id in importedIds) {
    if (claimed.contains(id) || books.seriesFor(id) != null) continue;
    final hint = books.seriesHint(id);
    if (hint == null) continue;
    final related = books.relatedVolumes(id);
    final targets = {
      for (final book in related) ?books.seriesFor(book.id)?.id,
    };
    final members = [
      id,
      for (final book in related)
        if (books.seriesFor(book.id) == null && !claimed.contains(book.id))
          book.id,
    ];
    if (targets.isEmpty && members.length < 2) continue;
    members.sort(
      (a, b) => (books.seriesHint(a)?.number ?? double.infinity).compareTo(
        books.seriesHint(b)?.number ?? double.infinity,
      ),
    );
    claimed.addAll(members);
    final target = targets.length == 1 ? books.seriesFor(targets.single) : null;
    groups.add(
      LocalImportGroup(
        seed: id,
        title: target?.title ?? hint.title,
        targetId: target?.id,
        needsTarget: targets.length > 1,
        volumes: [
          if (target != null)
            for (final volume in target.volumes)
              (bookId: volume.bookId, title: volume.title),
          for (final member in members)
            (
              bookId: member,
              title:
                  books.seriesHint(member)?.volumeTitle ??
                  books.book(member)?.title ??
                  '',
            ),
        ],
      ),
    );
  }
  return groups;
}
