import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/portable_book_prepare.dart';

void main() {
  late Directory root;
  late PortableBookPreparer preparer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('shiori-portable-');
    preparer = PortableBookPreparer(
      directory: Directory('${root.path}/work'),
      decodeNames: (names) async => [for (final _ in names) 'decoded.txt'],
      convert: (name, path) async => [(name: name, path: null, error: 'native')],
      extractKindle: (source, output) async => 2,
    );
    await PortableBookPreparer.clearPreviousRuns(preparer.directory);
  });

  tearDown(() => root.delete(recursive: true));

  Future<String> write(String name, List<int> bytes) async {
    final file = File('${root.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  ImportedBook parse(PreparedBookDocument prepared) => parseLocalBook(
    LocalBookInput(prepared.name, File(prepared.path!).readAsBytesSync()),
  );

  test('markdown headings become EPUB chapters', () async {
    final path = await write(
      'notes.md',
      utf8.encode('# 星尘邮局\n\n序言第一段。\n\n## 第一章 出发\n\n**清晨**出发。\n\n## 第二章 归来\n\n傍晚归来。\n'),
    );
    final [prepared] = await preparer.prepare('notes.md', path);
    expect(prepared.error, isNull);
    expect(prepared.name, 'notes.epub');
    final book = parse(prepared);
    expect(book.novel.title, '星尘邮局');
    final titles = book.novel.chapters.map((c) => c.title).toList();
    expect(titles, containsAll(['第一章 出发', '第二章 归来']));
    expect(book.bodies.join(), contains('清晨出发。'));
  });

  test('html splits on headings and ignores scripts', () async {
    final path = await write(
      'page.html',
      utf8.encode(
        '<html><head><title>风经过山谷</title><script>x()</script></head>'
        '<body><h1>上篇</h1><p>山谷里有风。</p><h2>下篇</h2><div><p>风停了。</p></div></body></html>',
      ),
    );
    final [prepared] = await preparer.prepare('page.html', path);
    final book = parse(prepared);
    expect(book.novel.title, '风经过山谷');
    expect(book.novel.chapters.length, 2);
    expect(book.bodies.join(), isNot(contains('x()')));
  });

  test('fb2 keeps author, sections and skips notes', () async {
    final path = await write(
      'book.fb2',
      utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<FictionBook><description><title-info><book-title>月光航线</book-title>'
        '<author><first-name>林</first-name><last-name>默</last-name></author></title-info></description>'
        '<body><section><title><p>第一章</p></title><p>船离港。</p></section>'
        '<section><title><p>第二章</p></title><p>船靠岸。</p></section></body>'
        '<body name="notes"><section><p>注释不应出现</p></section></body></FictionBook>',
      ),
    );
    final [prepared] = await preparer.prepare('book.fb2', path);
    final book = parse(prepared);
    expect(book.novel.title, '月光航线');
    expect(book.novel.author, '林 默');
    expect(book.novel.chapters.map((c) => c.title), ['第一章', '第二章']);
    expect(book.bodies.join(), isNot(contains('注释不应出现')));
  });

  test('docx headings split chapters', () async {
    String paragraph(String text, [String? style]) =>
        '<w:p>${style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>'}<w:r><w:t>$text</w:t></w:r></w:p>';
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'word/document.xml',
          utf8.encode(
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
            '${paragraph('第一章', 'Heading1')}${paragraph('正文一。')}'
            '${paragraph('第二章', 'Heading1')}${paragraph('正文二。')}'
            '</w:body></w:document>',
          ),
        ),
      );
    final path = await write('report.docx', ZipEncoder().encodeBytes(archive));
    final [prepared] = await preparer.prepare('report.docx', path);
    final book = parse(prepared);
    expect(book.novel.title, 'report');
    expect(book.novel.chapters.map((c) => c.title), ['第一章', '第二章']);
  });

  test('zip expands every book and skips junk entries', () async {
    final archive = Archive()
      ..add(ArchiveFile.bytes('a/第一卷.txt', utf8.encode('第一章\n正文')))
      ..add(ArchiveFile.bytes('b/notes.md', utf8.encode('# 札记\n\n内容')))
      ..add(ArchiveFile.bytes('__MACOSX/a/._第一卷.txt', [0, 1]))
      ..add(ArchiveFile.bytes('cover.jpg', [0xff, 0xd8]));
    final path = await write('pack.zip', ZipEncoder().encodeBytes(archive));
    final prepared = await preparer.prepare('pack.zip', path);
    expect(prepared.map((p) => p.name), ['第一卷.txt', 'notes.epub']);
    expect(prepared.every((p) => p.error == null), isTrue);
    await preparer.releasePaths(prepared.map((p) => p.path!));
    expect(prepared.every((p) => !File(p.path!).existsSync()), isTrue);
  });

  test('kindle failures map to readable messages', () async {
    final path = await write('book.mobi', Uint8List(16));
    final [prepared] = await preparer.prepare('book.mobi', path);
    expect(prepared.path, isNull);
    expect(prepared.error, '无法识别这个 Kindle 文件');
  });

  test('pdf without a native extractor explains itself', () async {
    final path = await write('scan.pdf', Uint8List(16));
    final [prepared] = await preparer.prepare('scan.pdf', path);
    expect(prepared.error, contains('PDF'));
  });
}
