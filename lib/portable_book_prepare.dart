import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import 'book_import_limits.dart';

typedef PreparedBookDocument = ({String name, String? path, String? error});

/// Turns the formats the reader cannot open directly into TXT or EPUB files
/// inside [directory]. Every output is disposable; callers hand the paths back
/// through [releasePaths] once the book is in the library.
class PortableBookPreparer {
  PortableBookPreparer({
    required this.directory,
    required this.decodeNames,
    required this.convert,
    required this.extractKindle,
    this.extractPdf,
  });
  final Directory directory;
  final Future<List<String>> Function(List<Uint8List> names) decodeNames;
  final Future<List<PreparedBookDocument>> Function(String name, String path)
  convert;
  final Future<int> Function(String source, String output) extractKindle;
  final Future<void> Function(String name, String source, String output)?
  extractPdf;
  var _runs = 0;

  static const _maxArchiveBooks = 500;
  static const _maxArchiveBytes = 1024 * 1024 * 1024;

  static Future<void> clearPreviousRuns(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  Future<Directory> _run() async {
    final run = Directory(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-${_runs++}',
    );
    return run.create(recursive: true);
  }

  Future<List<PreparedBookDocument>> prepare(String name, String path) async {
    final format = bookFormatKey(name);
    try {
      return switch (format) {
        'txt' || 'epub' => [(name: name, path: path, error: null)],
        'zip' => await _archive(name, path),
        'kindle' => [await _kindle(name, path)],
        'pdf' => [await _pdf(name, path)],
        'rtf' => await convert(name, path),
        'docx' || 'fb2' || 'html' || 'markdown' => [await _document(name, path, format)],
        _ => [(name: name, path: null, error: '暂不支持这种格式，请导入 EPUB 或 TXT')],
      };
    } on FormatException catch (error) {
      return [(name: name, path: null, error: error.message)];
    } on PlatformException catch (error) {
      return [(name: name, path: null, error: error.message ?? '无法转换这本书')];
    }
  }

  Future<void> releasePaths(Iterable<String> paths) async {
    // URI paths normalise separators, so mixed `/` and `\` still compare.
    final root = directory.absolute.uri.path;
    bool inside(FileSystemEntity entity) {
      final path = entity.absolute.uri.path;
      return path != root && path.startsWith(root);
    }

    for (final path in paths) {
      final file = File(path).absolute;
      if (!inside(file)) continue;
      if (await file.exists()) await file.delete();
      var parent = file.parent;
      while (inside(parent) &&
          await parent.exists() &&
          await parent.list().isEmpty) {
        await parent.delete();
        parent = parent.parent;
      }
    }
  }

  Future<List<PreparedBookDocument>> _archive(String name, String path) async {
    final input = InputFileStream(path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entries = [
        for (final file in archive)
          if (file.isFile &&
              !file.name.startsWith('__MACOSX/') &&
              !file.name.split('/').last.startsWith('.') &&
              supportsBookImport(file.name) &&
              bookFormatKey(file.name) != 'zip')
            file,
      ];
      if (entries.isEmpty) {
        throw const FormatException('压缩包中没有可导入的书籍');
      }
      if (entries.length > _maxArchiveBooks) {
        throw const FormatException('压缩包中的书籍过多，请分批导入');
      }
      final total = entries.fold<int>(0, (sum, e) => sum + e.size);
      if (total > _maxArchiveBytes) {
        throw const FormatException('压缩包展开后超过 1 GiB，请分批导入');
      }
      final names = await _entryNames(entries.map((e) => e.name).toList());
      final run = await _run();
      final results = <PreparedBookDocument>[];
      for (final (index, entry) in entries.indexed) {
        final label = names[index].split('/').last;
        if (entry.size > localBookByteLimit(label)) {
          results.add((name: label, path: null, error: localBookSizeMessage(label)));
          continue;
        }
        final target = File('${run.path}/$index-${_safe(label)}');
        final output = OutputFileStream(target.path);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
        results.addAll(await prepare(label, target.path));
      }
      return results;
    } on ArchiveException {
      throw const FormatException('压缩包已损坏，请重新下载');
    } finally {
      await input.close();
    }
  }

  // Non-UTF-8 names arrive as Latin-1 code units; the host decodes GBK/Big5.
  Future<List<String>> _entryNames(List<String> names) async {
    final raw = [
      for (final (i, name) in names.indexed)
        if (name.runes.any((c) => c >= 0x80) &&
            name.runes.every((c) => c <= 0xff))
          i,
    ];
    if (raw.isEmpty) return names;
    try {
      final decoded = await decodeNames([
        for (final i in raw) Uint8List.fromList(latin1.encode(names[i])),
      ]);
      final result = [...names];
      for (final (k, i) in raw.indexed) {
        result[i] = decoded[k];
      }
      return result;
    } catch (_) {
      return names;
    }
  }

  Future<PreparedBookDocument> _kindle(String name, String path) async {
    final run = await _run();
    final parts = Directory('${run.path}/oebps')..createSync();
    final status = await extractKindle(path, parts.path);
    if (status != 0) {
      throw FormatException(switch (status) {
        1 => '这本 Kindle 书受 DRM 保护，请选择未加密的原书',
        3 => 'Kindle 文件过大，无法转换',
        4 => '转换时无法写入文件，请检查存储空间',
        _ => '无法识别这个 Kindle 文件',
      });
    }
    final epub = File('${run.path}/${_safe(_base(name))}.epub');
    await Isolate.run(() => _packageOebps(parts.path, epub.path));
    await parts.delete(recursive: true);
    return (name: '${_base(name)}.epub', path: epub.path, error: null);
  }

  Future<PreparedBookDocument> _pdf(String name, String path) async {
    final extract = extractPdf;
    if (extract == null) {
      throw const FormatException('此设备暂不支持 PDF，请导入 EPUB 或 TXT');
    }
    final run = await _run();
    final output = File('${run.path}/${_safe(_base(name))}.txt');
    await extract(name, path, output.path);
    if (!await output.exists() || await output.length() == 0) {
      throw const FormatException('PDF 中没有可提取的文字，扫描版 PDF 暂不支持');
    }
    return (name: '${_base(name)}.txt', path: output.path, error: null);
  }

  Future<PreparedBookDocument> _document(
    String name,
    String path,
    String format,
  ) async {
    final run = await _run();
    final output = '${run.path}/${_safe(_base(name))}.epub';
    final fallback = _base(name);
    await Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      final book = switch (format) {
        'docx' => _docx(bytes, fallback),
        'fb2' => _fb2(bytes, fallback),
        'html' => _html(_text(bytes), fallback),
        _ => _markdown(_text(bytes), fallback),
      };
      File(output).writeAsBytesSync(_writeEpub(book));
    });
    return (name: '${_base(name)}.epub', path: output, error: null);
  }
}

String _base(String name) =>
    name.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '');

String _safe(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  final value = cleaned.isEmpty ? 'book' : cleaned;
  return value.length > 80 ? value.substring(0, 80) : value;
}

String _text(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return String.fromCharCodes(
      Uint16List.sublistView(Uint8List.fromList(bytes.sublist(2))),
    );
  }
  return utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
}

class _Chapter {
  _Chapter(this.title);
  final String title;
  final paragraphs = <String>[];
}

class _Book {
  _Book(this.title, this.author, this.chapters);
  final String title, author;
  final List<_Chapter> chapters;
}

const _chunkCharacters = 120000;

/// Untitled bodies become numbered parts so no single chapter grows past the
/// importer's per-chapter limit.
_Book _finish(String title, String author, List<_Chapter> chapters) {
  final result = <_Chapter>[];
  for (final chapter in chapters) {
    if (chapter.paragraphs.isEmpty && chapter.title.isEmpty) continue;
    var current = _Chapter(chapter.title.isEmpty ? title : chapter.title);
    var size = 0;
    var part = 1;
    for (final paragraph in chapter.paragraphs) {
      if (size > _chunkCharacters) {
        result.add(current);
        current = _Chapter('${chapter.title.isEmpty ? title : chapter.title}（${++part}）');
        size = 0;
      }
      current.paragraphs.add(paragraph);
      size += paragraph.length;
    }
    result.add(current);
  }
  if (result.every((c) => c.paragraphs.isEmpty)) {
    throw const FormatException('文件中没有可阅读的正文');
  }
  return _Book(title, author, result);
}

_Book _docx(Uint8List bytes, String fallback) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final document = archive.findFile('word/document.xml');
  if (document == null) throw const FormatException('这不是有效的 DOCX 文件');
  var title = fallback, author = '';
  if (archive.findFile('docProps/core.xml') case final core?) {
    final meta = XmlDocument.parse(utf8.decode(core.content, allowMalformed: true));
    String field(String local) =>
        meta.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == local)
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    if (field('title').isNotEmpty) title = field('title');
    author = field('creator');
  }
  final xml = XmlDocument.parse(utf8.decode(document.content, allowMalformed: true));
  final chapters = [_Chapter('')];
  final heading = RegExp(r'^(heading|title|标题)\s*[0-3]?$', caseSensitive: false);
  for (final p in xml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p')) {
    final buffer = StringBuffer();
    for (final node in p.descendants.whereType<XmlElement>()) {
      switch (node.name.local) {
        case 't':
          buffer.write(node.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br' || 'cr':
          buffer.write('\n');
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) continue;
    final style = p.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'pStyle')
        .firstOrNull
        ?.attributes
        .where((a) => a.name.local == 'val')
        .firstOrNull
        ?.value;
    final outline = p.descendants.any((e) => e is XmlElement && e.name.local == 'outlineLvl');
    if ((style != null && heading.hasMatch(style.replaceAll(RegExp(r'\s'), ''))) || outline) {
      chapters.add(_Chapter(text));
    } else {
      chapters.last.paragraphs.add(text);
    }
  }
  return _finish(title, author, chapters);
}

_Book _fb2(Uint8List bytes, String fallback) {
  final xml = XmlDocument.parse(_text(bytes));
  Iterable<XmlElement> all(XmlNode node, String local) =>
      node.descendants.whereType<XmlElement>().where((e) => e.name.local == local);
  final info = all(xml, 'title-info').firstOrNull;
  final title = (info == null ? null : all(info, 'book-title').firstOrNull?.innerText.trim()) ?? '';
  final author = info == null
      ? ''
      : [
          for (final part in ['first-name', 'middle-name', 'last-name'])
            ?all(info, part).firstOrNull?.innerText.trim(),
        ].where((s) => s.isNotEmpty).join(' ');
  final chapters = [_Chapter('')];
  void walk(XmlElement section) {
    final heading = section.childElements
        .where((e) => e.name.local == 'title')
        .map((e) => all(e, 'p').map((p) => p.innerText.trim()).join(' '))
        .firstOrNull;
    if (heading != null && heading.isNotEmpty) chapters.add(_Chapter(heading));
    for (final child in section.childElements) {
      switch (child.name.local) {
        case 'section':
          walk(child);
        case 'p' || 'subtitle' || 'v':
          final text = child.innerText.trim();
          if (text.isNotEmpty) chapters.last.paragraphs.add(text);
        case 'poem' || 'cite' || 'epigraph':
          for (final p in all(child, 'p').followedBy(all(child, 'v'))) {
            final text = p.innerText.trim();
            if (text.isNotEmpty) chapters.last.paragraphs.add(text);
          }
      }
    }
  }

  for (final body in all(xml, 'body').where((b) => b.getAttribute('name') != 'notes')) {
    walk(body);
  }
  return _finish(title.isEmpty ? fallback : title, author, chapters);
}

_Book _html(String source, String fallback) {
  final document = html.parse(source);
  final title = document.querySelector('title')?.text.trim() ?? '';
  final chapters = [_Chapter('')];
  const headings = {'h1', 'h2', 'h3'};
  const blocks = {'p', 'li', 'blockquote', 'pre', 'dd', 'dt', 'h4', 'h5', 'h6'};
  void walk(html.Node node) {
    for (final child in node.nodes) {
      if (child is html.Element) {
        final tag = child.localName ?? '';
        if (tag == 'script' || tag == 'style' || tag == 'head') continue;
        if (headings.contains(tag)) {
          final text = child.text.trim();
          if (text.isNotEmpty) chapters.add(_Chapter(text));
        } else if (blocks.contains(tag)) {
          for (final line in child.text.split('\n')) {
            if (line.trim().isNotEmpty) chapters.last.paragraphs.add(line.trim());
          }
        } else {
          walk(child);
        }
      } else if (child is html.Text && child.text.trim().isNotEmpty) {
        chapters.last.paragraphs.add(child.text.trim());
      }
    }
  }

  walk(document.body ?? document.documentElement!);
  return _finish(title.isEmpty ? fallback : title, '', chapters);
}

_Book _markdown(String source, String fallback) {
  final chapters = [_Chapter('')];
  var title = '';
  final paragraph = StringBuffer();
  void flush() {
    final text = paragraph.toString().trim();
    if (text.isNotEmpty) chapters.last.paragraphs.add(text);
    paragraph.clear();
  }

  String inline(String line) => line
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'(\*\*|__|`)'), '')
      .replaceAll(RegExp(r'^\s*(>\s*|[-*+]\s+|\d+\.\s+)'), '');
  for (final line in const LineSplitter().convert(source)) {
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      flush();
      final text = inline(heading[2]!).trim();
      if (heading[1]!.length == 1 && title.isEmpty) title = text;
      chapters.add(_Chapter(text));
    } else if (line.trim().isEmpty || RegExp(r'^\s*([-*_]\s*){3,}$').hasMatch(line)) {
      flush();
    } else {
      if (paragraph.isNotEmpty) paragraph.write(' ');
      paragraph.write(inline(line).trim());
    }
  }
  flush();
  return _finish(title.isEmpty ? fallback : title, '', chapters);
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

Uint8List _writeEpub(_Book book) {
  final archive = Archive();
  void add(String name, String content, {bool stored = false}) {
    final file = ArchiveFile.bytes(name, utf8.encode(content));
    if (stored) file.compression = CompressionType.none;
    archive.add(file);
  }

  add('mimetype', 'application/epub+zip', stored: true);
  add(
    'META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>',
  );
  final ids = [for (var i = 0; i < book.chapters.length; i++) 'c${i + 1}'];
  for (final (i, chapter) in book.chapters.indexed) {
    add(
      'OEBPS/${ids[i]}.xhtml',
      '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>${_escape(chapter.title)}</title></head><body>'
          '<h2>${_escape(chapter.title)}</h2>'
          '${chapter.paragraphs.map((p) => '<p>${_escape(p).replaceAll('\n', '<br/>')}</p>').join()}'
          '</body></html>',
    );
  }
  add(
    'OEBPS/nav.xhtml',
    '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body>'
        '<nav epub:type="toc"><ol>'
        '${[for (final (i, c) in book.chapters.indexed) '<li><a href="${ids[i]}.xhtml">${_escape(c.title)}</a></li>'].join()}'
        '</ol></nav></body></html>',
  );
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">shiori-${DateTime.now().microsecondsSinceEpoch}</dc:identifier>'
        '<dc:title>${_escape(book.title)}</dc:title>'
        '${book.author.isEmpty ? '' : '<dc:creator>${_escape(book.author)}</dc:creator>'}'
        '<dc:language>zh</dc:language>'
        '</metadata><manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        '${ids.map((id) => '<item id="$id" href="$id.xhtml" media-type="application/xhtml+xml"/>').join()}'
        '</manifest><spine>'
        '${ids.map((id) => '<itemref idref="$id"/>').join()}'
        '</spine></package>',
  );
  return ZipEncoder().encodeBytes(archive);
}

/// libmobi writes content.opf plus flat part/flow/resource files; wrapping
/// them with an OCF container makes a regular EPUB.
void _packageOebps(String folder, String output) {
  final archive = Archive();
  final mimetype = ArchiveFile.bytes('mimetype', utf8.encode('application/epub+zip'))
    ..compression = CompressionType.none;
  archive.add(mimetype);
  archive.add(
    ArchiveFile.bytes(
      'META-INF/container.xml',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>',
      ),
    ),
  );
  for (final entity in Directory(folder).listSync()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    archive.add(ArchiveFile.bytes('OEBPS/$name', entity.readAsBytesSync()));
  }
  if (!archive.files.any((f) => f.name == 'OEBPS/content.opf')) {
    throw const FormatException('无法识别这个 Kindle 文件');
  }
  File(output).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
}
