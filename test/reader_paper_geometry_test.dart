import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_paper_geometry.dart';

void main() {
  const size = Size(390, 700);

  ReaderPaperGeometry at(double progress, {double gap = 0}) =>
      ReaderPaperGeometry(size: size, gap: gap, progress: progress, touchY: .5);

  test('a resting sheet covers exactly its own page', () {
    final flat = at(0);
    expect(flat.lift, 0);
    final bounds = flat.front.outline.getBounds();
    expect(bounds.left, closeTo(0, .01));
    expect(bounds.right, closeTo(size.width, .01));
    expect(bounds.top, closeTo(0, .01));
    expect(bounds.bottom, closeTo(size.height, .01));
    expect(flat.back.outline.getBounds().isEmpty, isTrue);
  });

  test('a finished turn shows only the mirrored back', () {
    final done = at(1);
    expect(done.front.outline.getBounds().isEmpty, isTrue);
    final bounds = done.back.outline.getBounds();
    expect(bounds.left, closeTo(-size.width, .5));
    expect(bounds.right, closeTo(0, .5));
  });

  test('mid-turn the free edge leads and the faces split cleanly', () {
    final mid = at(.48);
    expect(mid.lift, greaterThan(.9));
    expect(mid.front.positions.length, greaterThan(6));
    expect(mid.back.positions.length, greaterThan(6));
    expect(mid.front.positions.length, mid.front.uv.length);
    final vertices = mid.front.positions.length ~/ 2;
    expect(mid.front.normals.length, vertices);
    expect(mid.front.indices.every((i) => i < vertices), isTrue);
  });

  test('the spine gap offsets the sheet from the hinge', () {
    final flat = at(0, gap: 12);
    expect(flat.front.outline.getBounds().left, closeTo(12, .01));
  });

  test('lifted paper is drawn larger than flat paper', () {
    final mid = at(.3).front.outline.getBounds();
    expect(mid.height, greaterThan(size.height));
  });
}
