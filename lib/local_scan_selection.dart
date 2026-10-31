import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'book_import_limits.dart';

/// Lists new or changed books from one folder scan. Everything starts
/// selected; the page returns the chosen tokens, or null when dismissed.
class LocalScanSelection extends StatefulWidget {
  const LocalScanSelection({super.key, required this.snapshot});
  final BookScanSnapshot snapshot;
  @override
  State<LocalScanSelection> createState() => _LocalScanSelectionState();
}

class _LocalScanSelectionState extends State<LocalScanSelection> {
  late final Set<String> _selected = {
    for (final book in widget.snapshot.books) book.token,
  };

  String _detail(BookScanEntry book) {
    final info = widget.snapshot.details[book.token];
    final format = bookFormatLabels[bookFormatKey(book.name)] ?? '';
    final size = info?.size;
    return [
      if (format.isNotEmpty) format,
      if (size != null) _bytes(size),
      if (info != null && info.folder.isNotEmpty) info.folder,
    ].join(' · ');
  }

  static String _bytes(int value) => value >= 1024 * 1024
      ? '${(value / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(value / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final books = widget.snapshot.books;
    final all = _selected.length == books.length;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      key: const ValueKey('local-scan-selection'),
      body: Atmosphere(
        child: GlassHeaderLayout(
          header: ArchiveHeaderBar(
            leading: GlassIconButton(
              icon: CupertinoIcons.back,
              label: '返回',
              onPressed: () => Navigator.pop(context),
            ),
            title: const ArchiveRouteTitle(
              title: '选择要导入的书',
              code: 'SCAN / SELECT',
            ),
            actions: [
              GlassIconButton(
                key: const ValueKey('scan-select-all'),
                icon: all
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.checkmark_circle,
                label: all ? '全不选' : '全选',
                onPressed: () => setState(() {
                  if (all) {
                    _selected.clear();
                  } else {
                    _selected.addAll(books.map((b) => b.token));
                  }
                }),
              ),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top +
                      FrostedHeader.toolbarHeight +
                      20,
                  24,
                  MediaQuery.paddingOf(context).bottom + 32,
                ),
                children: [
                  AppText(
                    '发现 ${books.length} 本新书或已更新的书'
                    '${widget.snapshot.unchanged > 0 ? '，${widget.snapshot.unchanged} 本已在书库' : ''}。',
                    style: TextStyle(fontSize: 13, height: 1.6, color: muted),
                  ),
                  for (final warning in widget.snapshot.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: AppText(
                        warning,
                        style: TextStyle(fontSize: 13, height: 1.6, color: muted),
                      ),
                    ),
                  const SizedBox(height: 16),
                  for (final book in books)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassTextButton(
                        key: ValueKey('scan-book-${book.token}'),
                        selected: _selected.contains(book.token),
                        onPressed: () => setState(() {
                          if (!_selected.remove(book.token)) {
                            _selected.add(book.token);
                          }
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              ArchiveIcon(
                                _selected.contains(book.token)
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 20,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(
                                      book.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_detail(book) case final detail
                                        when detail.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      AppText(
                                        detail,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  GlassTextButton(
                    key: const ValueKey('scan-import-selected'),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, Set.of(_selected)),
                    child: AppText(
                      _selected.isEmpty
                          ? '请选择书籍'
                          : '导入 ${_selected.length} 本',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
