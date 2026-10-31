import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'reading_widget_reference.dart';
import 'reading_widget_snapshot.dart';

/// Home-screen hosts cannot run Flutter, so cards are rasterised here with a
/// private pipeline that never touches the visible frame.
Future<Uint8List> renderReadingDesktopCard(
  ReadingWidgetSnapshot data,
  ReadingDesktopSize size, {
  required Brightness brightness,
  bool paintQuote = true,
  double pixelRatio = 3,
}) => _capture(
  ReadingDesktopCard(
    data: data,
    size: size,
    brightness: brightness,
    paintQuote: paintQuote,
  ),
  size.points,
  pixelRatio,
);

/// Faces for the classic widget, keyed by WidgetKit family name.
Future<Map<String, Uint8List>> renderReadingDesktopCards(
  ReadingWidgetSnapshot data,
) async => {
  for (final size in ReadingDesktopSize.values)
    size.name: await renderReadingDesktopCard(
      data,
      size,
      brightness: data.theme.isDark ? Brightness.dark : Brightness.light,
    ),
};

Future<Uint8List> _capture(Widget child, Size size, double pixelRatio) async {
  final boundary = RenderRepaintBoundary();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final owner = BuildOwner(focusManager: FocusManager());
  final element = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(size: size, devicePixelRatio: pixelRatio),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Localizations(
          locale: const Locale('zh', 'CN'),
          delegates: const [
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          child: child,
        ),
      ),
    ),
  ).attachToRenderTree(owner);
  try {
    // Localizations resolves asynchronously; let it settle before painting.
    owner.buildScope(element);
    await Future<void>.delayed(Duration.zero);
    owner.buildScope(element);
    owner.finalizeTree();
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    owner.finalizeTree();
    renderView.child = null;
    pipeline.rootNode = null;
    pipeline.dispose();
  }
}
