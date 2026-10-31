import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/local_books.dart';

/// Imports a real book end to end through the library store. Point SHIORI_EPUB
/// at any EPUB/TXT on this machine; skipped otherwise so CI needs no fixtures.
void main() {
  final path = Platform.environment['SHIORI_EPUB'];

  test('imports and reloads a real book', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final root = await Directory.systemTemp.createTemp('shiori-import-');
    try {
      final watch = Stopwatch()..start();
      final store = LocalBookStore(Directory('${root.path}/local-books-v1'));
      await store.load();
      final name = path!.replaceAll('\\', '/').split('/').last;
      final novel = await store.importFile(name, path);
      // ignore: avoid_print
      print('imported "${novel.title}" with ${novel.chapters.length} chapters in ${watch.elapsedMilliseconds} ms');
      expect(novel.chapters, isNotEmpty);
      final reloaded = LocalBookStore(Directory('${root.path}/local-books-v1'));
      await reloaded.load();
      expect(reloaded.books.map((b) => b.id), contains(novel.id));
    } finally {
      await root.delete(recursive: true);
    }
  }, skip: path == null ? 'set SHIORI_EPUB to a book file' : false, timeout: const Timeout(Duration(minutes: 10)));
}
