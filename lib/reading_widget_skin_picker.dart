import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'reading_widget_reference.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

/// Every card skin side by side, each previewed with the reader's real data.
class ReadingWidgetSkinPicker extends StatelessWidget {
  const ReadingWidgetSkinPicker({
    super.key,
    required this.previewBuilder,
    required this.value,
    required this.size,
    required this.snapshot,
    required this.onChanged,
  });
  final Widget Function(ReadingWidgetSkin skin) previewBuilder;
  final ReadingWidgetSkin value;
  final ReadingDesktopSize size;
  final ReadingWidgetSnapshot snapshot;
  final ValueChanged<ReadingWidgetSkin>? onChanged;

  @override
  Widget build(BuildContext context) {
    final skins = [
      for (final skin in ReadingWidgetSkin.values)
        if (skin != ReadingWidgetSkin.original) skin,
    ];
    final aspect = size.points.width / size.points.height;
    const height = 118.0;
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height + 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: skins.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final skin = skins[index];
          final selected = skin == value;
          return GestureDetector(
            key: ValueKey('reading-widget-skin-${skin.name}'),
            onTap: onChanged == null ? null : () => onChanged!(skin),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: selected ? accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: SizedBox(
                    height: height,
                    width: height * aspect,
                    child: FittedBox(child: previewBuilder(skin)),
                  ),
                ),
                const SizedBox(height: 6),
                AppText(
                  skin.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
