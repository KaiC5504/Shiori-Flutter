import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'reading_widget_design.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

/// Logical point sizes of the iPhone home-screen families the cards render at.
enum ReadingDesktopSize {
  small(Size(170, 170)),
  medium(Size(364, 170)),
  large(Size(364, 382));

  const ReadingDesktopSize(this.points);
  final Size points;
}

/// The face shared by the in-app preview and the PNGs handed to WidgetKit.
/// With [paintQuote] off, the quote card leaves its text to the native host.
class ReadingDesktopCard extends StatelessWidget {
  const ReadingDesktopCard({
    super.key,
    required this.data,
    required this.size,
    required this.brightness,
    this.quoteText,
    this.quoteSource = '',
    this.quoteCount = 0,
    this.paintQuote = true,
  });
  final ReadingWidgetSnapshot data;
  final ReadingDesktopSize size;
  final Brightness brightness;
  final String? quoteText;
  final String quoteSource;
  final int quoteCount;
  final bool paintQuote;

  ReadingWidgetSkin get _skin => data.skin == ReadingWidgetSkin.original
      ? ReadingWidgetSkin.seasons
      : data.skin;

  @override
  Widget build(BuildContext context) {
    final skin = _skin;
    final palette = _Palette(
      background: skin.background(brightness),
      foreground: skin.foreground(brightness),
      accent: skin.accent(data.localDay),
    );
    return SizedBox.fromSize(
      size: size.points,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DefaultTextStyle(
          style: TextStyle(
            color: palette.foreground,
            fontSize: 13,
            height: 1.3,
            decoration: TextDecoration.none,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: palette.background),
              CustomPaint(
                painter: _SkinPainter(skin, palette, data.localDay),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: switch (data.design) {
                  ReadingWidgetDesign.week => _week(palette),
                  ReadingWidgetDesign.calendar => _calendar(palette),
                  ReadingWidgetDesign.memory => _memory(palette),
                  ReadingWidgetDesign.quote => _quote(palette),
                  _ => _focus(palette),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _small => size == ReadingDesktopSize.small;

  Widget _label(String text, _Palette palette) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w600,
      color: palette.muted,
    ),
  );

  Widget _focus(_Palette palette) {
    final minutes = (data.verifiedTodaySeconds ?? 0) ~/ 60;
    final goal = data.dailyGoalMinutes;
    final streak = data.qualifiedStreakDays ?? 0;
    final book = data.showBookDetails ? data.currentBook : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('今日阅读', palette),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$minutes',
              style: TextStyle(
                fontSize: _small ? 46 : 54,
                fontWeight: FontWeight.w700,
                height: 1,
                color: palette.foreground,
              ),
            ),
            const SizedBox(width: 6),
            Text('分钟', style: TextStyle(color: palette.muted)),
          ],
        ),
        const SizedBox(height: 10),
        if (goal > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (minutes / goal).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: palette.track,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          [
            if (goal > 0) readingGoalCaption(goal, data.verifiedTodaySeconds),
            if (streak > 0) '连续 $streak 天',
          ].join(' · ').ifEmpty('留一点时间给故事'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: palette.muted),
        ),
        if (book != null && !_small) ...[
          const SizedBox(height: 12),
          Text(
            book.title,
            maxLines: size == ReadingDesktopSize.large ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Text(
            book.chapter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
        ],
        if (size == ReadingDesktopSize.large) const Spacer(flex: 2),
      ],
    );
  }

  Widget _week(_Palette palette) {
    final days = data.week;
    final peak = days.fold<int>(
      1,
      (most, day) => math.max(most, day.verifiedSeconds ?? 0),
    );
    final total = (data.weekSeconds ?? 0) ~/ 60;
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('本周阅读', palette),
        const SizedBox(height: 6),
        Text(
          '$total 分钟',
          style: TextStyle(
            fontSize: _small ? 20 : 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: _small ? 3 : 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: math.max(
                              .06,
                              (day.verifiedSeconds ?? 0) / peak,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: (day.verifiedSeconds ?? 0) >=
                                        ReadingWidgetSnapshot
                                            .qualificationSeconds
                                    ? palette.accent
                                    : palette.track,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          names[day.date.weekday - 1],
                          style: TextStyle(fontSize: 10, color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _calendar(_Palette palette) {
    final weeks = switch (size) {
      ReadingDesktopSize.small => 8,
      ReadingDesktopSize.medium => 20,
      ReadingDesktopSize.large => 22,
    };
    final days = data.heatmap.window(weeks);
    final active = days.where((d) => (d.verifiedSeconds ?? 0) > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('阅读日历', palette),
            const Spacer(),
            Text(
              '$active 天',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cell = math.min(
                constraints.maxWidth / weeks,
                constraints.maxHeight / 7,
              );
              return Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: cell * weeks,
                  height: cell * 7,
                  child: CustomPaint(
                    painter: _HeatmapPainter(days, weeks, cell, palette),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _memory(_Palette palette) {
    final done = data.latestCompletion;
    final title = done == null
        ? null
        : data.showBookDetails
        ? done.title ?? '一本书'
        : '一本书';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('阅读纪念', palette),
        const Spacer(),
        if (done == null)
          Text(
            '读完一本书后，\n这里会留下纪念。',
            style: TextStyle(fontSize: 14, height: 1.5, color: palette.muted),
          )
        else ...[
          Text(
            done.finished ? '读完了' : '读到了',
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
          const SizedBox(height: 4),
          Text(
            '《$title》',
            maxLines: _small ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _small ? 17 : 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (data.showBookDetails && (done.author ?? '').isNotEmpty)
            Text(
              done.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          const SizedBox(height: 8),
          Text(
            '${done.completedAt.year}.${done.completedAt.month.toString().padLeft(2, '0')}.${done.completedAt.day.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1,
              color: palette.accent,
            ),
          ),
        ],
        if (!_small) const Spacer(),
      ],
    );
  }

  Widget _quote(_Palette palette) {
    final text = quoteText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label('摘录', palette),
            const Spacer(),
            Text(
              '“',
              style: TextStyle(
                fontSize: 34,
                height: .8,
                color: palette.accent.withValues(alpha: .7),
              ),
            ),
          ],
        ),
        if (paintQuote) ...[
          const Spacer(),
          Text(
            text ?? '在阅读时长按句子，加入书签后会出现在这里。',
            maxLines: _small ? 5 : size == ReadingDesktopSize.large ? 10 : 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: text == null ? 13 : 15,
              height: 1.6,
              color: text == null ? palette.muted : palette.foreground,
            ),
          ),
          if (text != null && quoteSource.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '— $quoteSource',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
          ],
          const Spacer(),
        ],
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _Palette {
  _Palette({
    required this.background,
    required this.foreground,
    required this.accent,
  });
  final Color background, foreground, accent;
  Color get muted => foreground.withValues(alpha: .62);
  Color get track => foreground.withValues(alpha: .1);
}

class _SkinPainter extends CustomPainter {
  _SkinPainter(this.skin, this.palette, this.day);
  final ReadingWidgetSkin skin;
  final _Palette palette;
  final DateTime day;

  @override
  void paint(Canvas canvas, Size size) {
    switch (skin) {
      case ReadingWidgetSkin.seasons || ReadingWidgetSkin.original:
        final width = size.width / 4;
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(
            Rect.fromLTWH(i * width, size.height - 5, width, 5),
            Paint()..color = ReadingWidgetSkin.seasonColors[i],
          );
        }
        final glyph = TextPainter(
          text: TextSpan(
            text: const ['春', '夏', '秋', '冬'][ReadingWidgetSkin.season(day)],
            style: TextStyle(
              fontSize: 62,
              fontWeight: FontWeight.w700,
              color: palette.accent.withValues(alpha: .13),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        glyph.paint(canvas, Offset(size.width - glyph.width - 12, 4));
      case ReadingWidgetSkin.archive:
        final tab = Path()
          ..moveTo(size.width - 54, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, 54)
          ..close();
        canvas.drawPath(tab, Paint()..color = palette.accent.withValues(alpha: .8));
      case ReadingWidgetSkin.paper:
        canvas.save();
        canvas.translate(size.width - 28, 6);
        canvas.rotate(7 * math.pi / 180);
        canvas.drawRect(
          const Rect.fromLTWH(-12, -6, 24, 13),
          Paint()..color = palette.accent.withValues(alpha: .3),
        );
        canvas.restore();
      case ReadingWidgetSkin.night:
        final center = Offset(size.width - 25, 25);
        canvas.drawCircle(center, 8, Paint()..color = palette.accent);
        canvas.drawCircle(
          center + const Offset(4, -4),
          8,
          Paint()..color = palette.background,
        );
      case ReadingWidgetSkin.film:
        final hole = Paint()..color = const Color(0xffd6d2c7).withValues(alpha: .5);
        for (var y = 10.0; y < size.height - 8; y += 18) {
          for (final x in [4.0, size.width - 10]) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, 6, 9),
                const Radius.circular(1.5),
              ),
              hole,
            );
          }
        }
    }
  }

  @override
  bool shouldRepaint(_SkinPainter old) =>
      old.skin != skin || old.day != day || old.palette.accent != palette.accent;
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter(this.days, this.weeks, this.cell, this.palette);
  final List<ReadingWidgetDay> days;
  final int weeks;
  final double cell;
  final _Palette palette;

  static double _level(int? seconds) => switch (seconds ?? 0) {
    0 => 0,
    < 300 => .26,
    < 900 => .48,
    < 1800 => .72,
    _ => 1,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final gap = math.max(1.5, cell * .16);
    for (final (index, day) in days.indexed) {
      final column = index ~/ 7, row = index % 7;
      final level = _level(day.verifiedSeconds);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            column * cell + gap / 2,
            row * cell + gap / 2,
            cell - gap,
            cell - gap,
          ),
          Radius.circular(cell * .22),
        ),
        Paint()
          ..color = level == 0
              ? palette.track
              : palette.accent.withValues(alpha: level),
      );
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) => old.days != days || old.cell != cell;
}
