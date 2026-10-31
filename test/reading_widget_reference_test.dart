import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reading_widget_design.dart';
import 'package:wenku8_flutter/reading_widget_reference.dart';
import 'package:wenku8_flutter/reading_widget_reference_capture.dart';
import 'package:wenku8_flutter/reading_widget_skin.dart';
import 'package:wenku8_flutter/reading_widget_snapshot.dart';

ReadingWidgetSnapshot snapshot(ReadingWidgetDesign design, ReadingWidgetSkin skin) {
  final day = DateTime(2026, 10, 31);
  return ReadingWidgetSnapshot(
    generatedAt: day,
    localDay: day,
    verifiedTotalSeconds: 36000,
    verifiedTodaySeconds: 1260,
    qualifiedStreakDays: 4,
    week: [
      for (var i = 0; i < 7; i++)
        ReadingWidgetDay(
          date: DateTime(day.year, day.month, day.day - 6 + i),
          verifiedSeconds: [0, 600, 1800, null, 300, 2400, 1260][i],
        ),
    ],
    design: design,
    skin: skin,
    dailyGoalMinutes: 30,
  );
}

void main() {
  testWidgets('every design and skin lays out at every size', (tester) async {
    for (final design in ReadingWidgetDesign.values) {
      for (final skin in ReadingWidgetSkin.values) {
        for (final size in ReadingDesktopSize.values) {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: ReadingDesktopCard(
                  data: snapshot(design, skin),
                  size: size,
                  brightness: Brightness.light,
                  quoteText: '风从山谷里经过，带走了一整个夏天。',
                  quoteSource: '风经过山谷',
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull, reason: '$design $skin $size');
        }
      }
    }
  });

  testWidgets('cards rasterise to PNG for WidgetKit', (tester) async {
    late Uint8List bytes;
    await tester.runAsync(() async {
      bytes = await renderReadingDesktopCard(
        snapshot(ReadingWidgetDesign.week, ReadingWidgetSkin.seasons),
        ReadingDesktopSize.medium,
        brightness: Brightness.dark,
        pixelRatio: 2,
      );
    });
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
    expect(bytes.length, greaterThan(1000));
  });

  test('goal captions', () {
    expect(readingGoalCaption(30, 600), '今日 10 / 30 分钟');
    expect(readingGoalCaption(30, 1800), '今日目标已完成 · 30 分钟');
    expect(readingDailyGoal(null), 0);
    expect(ReadingWidgetSkin.fromId('nope'), ReadingWidgetSkin.original);
  });
}
