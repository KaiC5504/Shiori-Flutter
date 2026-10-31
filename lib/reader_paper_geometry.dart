import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// One face of the turning sheet in canonical space: the spine is x = 0 and
/// the flat sheet extends to +x. [uv] stays in page-local logical pixels.
class ReaderPaperMesh {
  ReaderPaperMesh._(
    this.positions,
    this.uv,
    this.indices,
    this.normals,
    this.outline,
  );

  // A zero-area triangle keeps Vertices.raw valid when a face is hidden.
  factory ReaderPaperMesh.empty() => ReaderPaperMesh._(
    Float32List(6),
    Float32List(6),
    Uint16List.fromList(const [0, 1, 2]),
    const [1, 1, 1],
    Path(),
  );

  final Float32List positions, uv;
  final Uint16List indices;

  /// Facing ratio per vertex: 1 flat towards the reader, 0 edge-on.
  final List<double> normals;
  final Path outline;
}

/// The sheet rotates about the spine and its free edge leads slightly, so the
/// paper bends instead of swinging as a rigid board. Lifted paper is drawn a
/// little larger because it is nearer the reader.
class ReaderPaperGeometry {
  ReaderPaperGeometry({
    required this.size,
    required this.gap,
    required double progress,
    required double touchY,
  }) {
    final p = progress.clamp(0.0, 1.0);
    lift = math.sin(p * math.pi);
    final width = size.width, height = size.height;
    final reach = width + gap;
    final pivotY = height * touchY.clamp(0.0, 1.0);
    double angle(double u) => math
        .min(
          math.pi,
          p * math.pi + _bend * lift * math.pow(u / width, 1.5).toDouble(),
        )
        .toDouble();

    final columns = <double>[
      for (var i = 0; i <= _columns; i++) width * i / _columns,
    ];
    double? split;
    if (angle(0) < math.pi / 2 && angle(width) > math.pi / 2) {
      var low = 0.0, high = width;
      for (var i = 0; i < 24; i++) {
        final mid = (low + high) / 2;
        if (angle(mid) < math.pi / 2) {
          low = mid;
        } else {
          high = mid;
        }
      }
      split = (low + high) / 2;
      columns
        ..add(split)
        ..sort();
    }

    ReaderPaperMesh face(Iterable<double> us) {
      final cols = us.toList();
      if (cols.length < 2 || cols.last - cols.first < .01) {
        return ReaderPaperMesh.empty();
      }
      final positions = Float32List(cols.length * (_rows + 1) * 2);
      final uv = Float32List(positions.length);
      final normals = List<double>.filled(cols.length * (_rows + 1), 0);
      final top = <Offset>[], bottom = <Offset>[];
      var v = 0;
      for (final u in cols) {
        final theta = angle(u), radius = gap + u;
        final depth = radius * math.sin(theta) / reach;
        final scale = 1 + _perspective * depth;
        final x = radius * math.cos(theta) * scale;
        for (var r = 0; r <= _rows; r++) {
          final y = height * r / _rows;
          final projected = pivotY + (y - pivotY) * scale;
          positions[v * 2] = x;
          positions[v * 2 + 1] = projected;
          uv[v * 2] = u;
          uv[v * 2 + 1] = y;
          normals[v] = math.cos(theta).abs();
          if (r == 0) top.add(Offset(x, projected));
          if (r == _rows) bottom.add(Offset(x, projected));
          v++;
        }
      }
      final indices = Uint16List((cols.length - 1) * _rows * 6);
      var i = 0;
      for (var c = 0; c < cols.length - 1; c++) {
        for (var r = 0; r < _rows; r++) {
          final a = c * (_rows + 1) + r, b = a + _rows + 1;
          indices.setAll(i, [a, b, a + 1, a + 1, b, b + 1]);
          i += 6;
        }
      }
      final outline = Path()..addPolygon([...top, ...bottom.reversed], true);
      return ReaderPaperMesh._(positions, uv, indices, normals, outline);
    }

    final facing = angle(0) < math.pi / 2;
    if (split != null) {
      front = face(columns.where((u) => u <= split!));
      back = face(columns.where((u) => u >= split!));
    } else if (facing) {
      front = face(columns);
      back = ReaderPaperMesh.empty();
    } else {
      front = ReaderPaperMesh.empty();
      back = face(columns);
    }
    sheet = Path()
      ..addPath(front.outline, Offset.zero)
      ..addPath(back.outline, Offset.zero);
  }

  static const _columns = 28, _rows = 6;
  static const _bend = .42, _perspective = .07;

  final Size size;
  final double gap;
  late final double lift;
  late final ReaderPaperMesh front, back;

  /// The text texture shares the paper surface exactly.
  ReaderPaperMesh get frontInk => front;
  ReaderPaperMesh get backInk => back;

  /// Everything the turning sheet covers, front and back together.
  late final Path sheet;
}
