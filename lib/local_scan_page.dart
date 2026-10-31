import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'book_documents.dart';
import 'book_import_limits.dart';
import 'local_book_scanner.dart';
import 'local_import_batch.dart';

/// iOS cannot scan arbitrary storage: the user grants one folder (or uses the
/// App's own Documents folder, shown in Files), which is rescanned on entry.
class LocalScanPage extends StatefulWidget {
  const LocalScanPage({
    super.key,
    required this.documents,
    required this.changes,
    required this.isBusy,
    required this.progress,
    required this.result,
    required this.failure,
    required this.onScan,
  });
  final BookDocuments documents;
  final Listenable changes;
  final bool Function() isBusy;
  final (int, int)? Function() progress;
  final LocalScanResult? Function() result;
  final String? Function() failure;
  final Future<void> Function(BuildContext) onScan;
  @override
  State<LocalScanPage> createState() => _LocalScanPageState();
}

class _LocalScanPageState extends State<LocalScanPage> {
  BookScanFolder? _folder;
  Set<String> _formats = const {};
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final folder = await widget.documents.scanFolderInfo();
      final formats = await widget.documents.scanFormats();
      if (!mounted) return;
      setState(() {
        _folder = folder;
        _formats = formats;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) => localImportFailureMessage(error);

  Future<void> _act(Future<void> Function() action) async {
    if (_saving || widget.isBusy()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _choose({bool appFolder = false}) => _act(() async {
    final folder = appFolder
        ? await widget.documents.selectAllScan()
        : await widget.documents.selectScanFolder();
    if (folder == null || !mounted) return;
    setState(() => _folder = folder);
    await widget.documents.setScanAutomatic(true);
    if (mounted) {
      setState(() => _folder = BookScanFolder(
        name: folder.name,
        automatic: true,
        readable: folder.readable,
        allStorage: folder.allStorage,
      ));
      await widget.onScan(context);
    }
  });

  Future<void> _automatic(bool value) => _act(() async {
    await widget.documents.setScanAutomatic(value);
    final folder = _folder;
    if (folder != null && mounted) {
      setState(() => _folder = BookScanFolder(
        name: folder.name,
        automatic: value,
        readable: folder.readable,
        allStorage: folder.allStorage,
      ));
    }
  });

  Future<void> _toggleFormat(String format) => _act(() async {
    final next = {..._formats};
    if (!next.remove(format)) next.add(format);
    if (next.isEmpty) throw const FormatException('至少保留一种格式');
    await widget.documents.setScanFormats(next);
    if (mounted) setState(() => _formats = next);
  });

  Future<void> _disconnect() => _act(() async {
    await widget.documents.disconnectScanFolder();
    if (mounted) setState(() => _folder = null);
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.changes,
    builder: (context, _) {
      final busy = _saving || _loading || widget.isBusy();
      final folder = _folder;
      final progress = widget.progress();
      final result = widget.result();
      final error = _error ?? widget.failure();
      final muted = TextStyle(
        fontSize: 13,
        height: 1.6,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
      return Scaffold(
        key: const ValueKey('local-scan-page'),
        body: Atmosphere(
          child: GlassHeaderLayout(
            header: ArchiveHeaderBar(
              leading: GlassIconButton(
                icon: CupertinoIcons.back,
                label: '返回',
                onPressed: () => Navigator.pop(context),
              ),
              title: const ArchiveRouteTitle(
                title: '扫描文件夹',
                code: 'LOCAL / SCAN',
              ),
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
                    const ArchiveSection(title: '书籍文件夹', code: '01 / FOLDER'),
                    const SizedBox(height: 14),
                    ContentPanel(
                      key: const ValueKey('scan-folder-status'),
                      child: Row(
                        children: [
                          ArchiveIcon(
                            folder == null
                                ? CupertinoIcons.folder_badge_plus
                                : CupertinoIcons.folder_fill,
                            size: 26,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  folder == null
                                      ? '尚未选择文件夹'
                                      : folder.allStorage
                                      ? '“文件”App › 我的 iPhone › Shiori'
                                      : folder.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AppText(
                                  folder == null
                                      ? '选择一个文件夹，放进去的书会自动出现在书架上。'
                                      : !folder.readable
                                      ? '文件夹的访问授权已失效，请重新选择。'
                                      : folder.automatic
                                      ? '每次打开书架时自动导入新书。'
                                      : '仅在点击“立即扫描”时导入。',
                                  style: muted,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    GlassTextButton(
                      key: const ValueKey('scan-choose-folder'),
                      onPressed: busy ? null : _choose,
                      child: AppText(
                        folder == null ? '选择文件夹' : '更换文件夹',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GlassTextButton(
                      key: const ValueKey('scan-app-folder'),
                      onPressed: busy ? null : () => _choose(appFolder: true),
                      child: const AppText(
                        '使用 App 自带文件夹',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      'App 自带文件夹位于“文件”App 的“我的 iPhone › Shiori”，可从电脑或其他 App 直接拷入书籍。',
                      style: muted,
                    ),
                    if (folder != null) ...[
                      const SizedBox(height: 28),
                      const ArchiveSection(title: '自动导入', code: '02 / AUTO'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Expanded(child: AppText('打开书架时自动扫描并导入')),
                          AppControls.toggle(
                            context,
                            key: const ValueKey('scan-automatic'),
                            value: folder.automatic,
                            onChanged: busy ? null : _automatic,
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),
                    const ArchiveSection(title: '扫描格式', code: '03 / FORMATS'),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in bookFormatLabels.entries)
                          if (entry.key != 'doc')
                            GlassTextButton(
                              key: ValueKey('scan-format-${entry.key}'),
                              compact: true,
                              selected: _formats.contains(entry.key),
                              onPressed: busy
                                  ? null
                                  : () => _toggleFormat(entry.key),
                              child: AppText(entry.value),
                            ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    GlassTextButton(
                      key: const ValueKey('scan-now'),
                      onPressed: busy || folder == null || !folder.readable
                          ? null
                          : () => widget.onScan(context),
                      child: const AppText('立即扫描', textAlign: TextAlign.center),
                    ),
                    if (widget.isBusy()) ...[
                      const SizedBox(height: 12),
                      RefreshProgress(
                        label: progress == null
                            ? '正在扫描文件夹'
                            : '正在导入 ${progress.$1} / ${progress.$2} 本',
                      ),
                    ],
                    if (result != null && !widget.isBusy())
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: AppText(result.summary, style: muted),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: AppText(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (folder != null) ...[
                      const SizedBox(height: 28),
                      GlassTextButton(
                        key: const ValueKey('scan-disconnect'),
                        onPressed: busy ? null : _disconnect,
                        child: const AppText(
                          '断开文件夹',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AppText('断开后已导入的书仍保留在书库。', style: muted),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
