import 'dart:ui';

/// Must match `ReadingWidgetSkin` in ios/ReadingWidgets/ReadingWidgetTheme.swift:
/// the native face and the rendered cards draw the same palettes.
enum ReadingWidgetSkin {
  original('随主题', '沿用阅读主题配色'),
  seasons('四季', '随月份更替色彩'),
  archive('档案', '索引卡与印记'),
  paper('纸页', '米白纸张与胶带'),
  night('夜读', '深色与一弯月亮'),
  film('胶片', '暗房里的片孔');

  const ReadingWidgetSkin(this.label, this.description);
  final String label, description;

  static ReadingWidgetSkin fromId(String? value) =>
      values.where((skin) => skin.name == value).firstOrNull ?? original;

  static const seasonColors = [
    Color(0xffaf7d8b),
    Color(0xff5786a2),
    Color(0xffb18842),
    Color(0xff4f8985),
  ];

  static int season(DateTime day) => switch (day.month) {
    3 || 4 || 5 => 0,
    6 || 7 || 8 => 1,
    9 || 10 || 11 => 2,
    _ => 3,
  };

  bool get dark => this == night || this == film;

  Color background(Brightness brightness) => switch (this) {
    night => const Color(0xff101419),
    film => const Color(0xff10100f),
    paper => brightness == Brightness.dark
        ? const Color(0xff1c1d1a)
        : const Color(0xffecece5),
    _ => brightness == Brightness.dark
        ? const Color(0xff17191a)
        : const Color(0xfff4f0e6),
  };

  Color foreground(Brightness brightness) =>
      dark || brightness == Brightness.dark
      ? const Color(0xfff6f1e6)
      : const Color(0xff272c29);

  Color accent(DateTime day) => switch (this) {
    seasons => seasonColors[season(day)],
    night || film => const Color(0xffdcb65e),
    paper => const Color(0xff606d5d),
    _ => const Color(0xff4f8985),
  };
}

const readingGoalChoices = [0, 15, 30, 60];

int readingDailyGoal(int? minutes) => (minutes ?? 0).clamp(0, 600);

String readingGoalCaption(int goalMinutes, int? todaySeconds) {
  final minutes = (todaySeconds ?? 0) ~/ 60;
  if (goalMinutes <= 0) return '今日已读 $minutes 分钟';
  if (minutes >= goalMinutes) return '今日目标已完成 · $minutes 分钟';
  return '今日 $minutes / $goalMinutes 分钟';
}
