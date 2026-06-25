import 'package:flutter/material.dart';

import '../utils/sleep_metrics.dart';
import '../utils/sleep_series.dart';

const _muted = Color(0xFF888899);
const _grid = Color(0xFF2A2A45);

const _awakeColor = Color(0xFFE84393);
const _remColor = Color(0xFFB39DFF);
const _lightColor = Color(0xFF7C6FF0);
const _deepColor = Color(0xFF4834D4);

Color _stageColor(SleepStage s) => switch (s) {
      SleepStage.awake => _awakeColor,
      SleepStage.rem => _remColor,
      SleepStage.light => _lightColor,
      SleepStage.deep => _deepColor,
    };

String _fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'am' : 'pm';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
}

void _label(Canvas canvas, String text, Offset at,
    {Color color = _muted,
    double size = 9,
    TextAlign align = TextAlign.left,
    double width = 60}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size)),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout(maxWidth: width);
  var dx = at.dx;
  if (align == TextAlign.right) dx = at.dx - tp.width;
  if (align == TextAlign.center) dx = at.dx - tp.width / 2;
  tp.paint(canvas, Offset(dx, at.dy));
}

// ─── Hypnogram ────────────────────────────────────────────────────────────────

/// Samsung-style sleep-stage chart: Awake / REM / Light / Deep bands with the
/// stepped sleep waveform and pink awake tics. Time on X, stage on Y.
class SleepHypnogram extends StatelessWidget {
  final List<SleepStageSegment> segments;
  const SleepHypnogram({super.key, required this.segments});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: CustomPaint(painter: _HypnogramPainter(segments)),
    );
  }
}

class _HypnogramPainter extends CustomPainter {
  final List<SleepStageSegment> segments;
  _HypnogramPainter(this.segments);

  static const _bands = [
    SleepStage.awake,
    SleepStage.rem,
    SleepStage.light,
    SleepStage.deep,
  ];
  static const _labels = ['Awake', 'REM', 'Light', 'Deep'];

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    const leftPad = 40.0;
    const bottomPad = 18.0;
    final plotW = size.width - leftPad;
    final plotH = size.height - bottomPad;
    final start = segments.first.start;
    final end = segments.last.end;
    final totalMs = end.difference(start).inMilliseconds;
    if (totalMs <= 0) return;

    final bandH = plotH / _bands.length;
    double bandCenter(SleepStage s) =>
        _bands.indexOf(s) * bandH + bandH / 2;
    double x(DateTime t) =>
        leftPad + plotW * (t.difference(start).inMilliseconds / totalMs);

    // Y labels + faint band separators.
    final gridP = Paint()
      ..color = _grid.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (var i = 0; i < _bands.length; i++) {
      final y = i * bandH + bandH / 2;
      _label(canvas, _labels[i], Offset(0, y - 6), width: leftPad - 6);
      canvas.drawLine(Offset(leftPad, i * bandH + bandH),
          Offset(size.width, i * bandH + bandH), gridP);
    }

    // Stepped connectors between consecutive non-awake stages.
    final sleep = segments.where((s) => s.stage != SleepStage.awake).toList();
    final connP = Paint()
      ..color = _lightColor.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < sleep.length - 1; i++) {
      final bx = x(sleep[i].end);
      canvas.drawLine(Offset(bx, bandCenter(sleep[i].stage)),
          Offset(bx, bandCenter(sleep[i + 1].stage)), connP);
    }

    final fill = Paint()..style = PaintingStyle.fill;
    const barH = 10.0;
    for (final seg in segments) {
      final left = x(seg.start);
      final right = x(seg.end);
      fill.color = _stageColor(seg.stage);
      if (seg.stage == SleepStage.awake) {
        // Thin pink tic at the top, like Samsung.
        final r = Rect.fromLTRB(left, 2, (right - left) < 2 ? left + 2 : right,
            bandH * 0.7);
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(1)), fill);
      } else {
        final cy = bandCenter(seg.stage);
        final r = Rect.fromLTRB(left, cy - barH / 2,
            (right - left) < 2 ? left + 2 : right, cy + barH / 2);
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(3)), fill);
      }
    }

    // X time labels: start, ⅓, ⅔, end.
    for (var i = 0; i <= 3; i++) {
      final t = start.add(Duration(milliseconds: (totalMs * i / 3).round()));
      final align = i == 0
          ? TextAlign.left
          : i == 3
              ? TextAlign.right
              : TextAlign.center;
      _label(canvas, _fmtTime(t),
          Offset(leftPad + plotW * i / 3, plotH + 4),
          align: align, width: 60);
    }
  }

  @override
  bool shouldRepaint(covariant _HypnogramPainter old) =>
      old.segments != segments;
}

// ─── Stage bar with typical-range marker ─────────────────────────────────────

/// A horizontal stage bar (0..1 [value]) with a hatched "typical range" band
/// between [rangeLow] and [rangeHigh], like Samsung's breakdown.
class StageBar extends StatelessWidget {
  final double value;
  final double rangeLow;
  final double rangeHigh;
  final Color color;
  const StageBar({
    super.key,
    required this.value,
    required this.rangeLow,
    required this.rangeHigh,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      width: double.infinity,
      child: CustomPaint(
        painter: _StageBarPainter(
          value: value.clamp(0.0, 1.0),
          rangeLow: rangeLow.clamp(0.0, 1.0),
          rangeHigh: rangeHigh.clamp(0.0, 1.0),
          color: color,
        ),
      ),
    );
  }
}

class _StageBarPainter extends CustomPainter {
  final double value, rangeLow, rangeHigh;
  final Color color;
  _StageBarPainter({
    required this.value,
    required this.rangeLow,
    required this.rangeHigh,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height), radius);
    // Track.
    canvas.drawRRect(track, Paint()..color = const Color(0xFF0D0D1A));

    // Hatched typical-range band.
    final bandRect = Rect.fromLTWH(size.width * rangeLow, 0,
        size.width * (rangeHigh - rangeLow), size.height);
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(bandRect, Paint()..color = _grid.withValues(alpha: 0.6));
    final hatch = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (double dx = bandRect.left - size.height;
        dx < bandRect.right;
        dx += 4) {
      canvas.drawLine(
          Offset(dx, size.height), Offset(dx + size.height, 0), hatch);
    }
    canvas.restore();

    // Value fill.
    if (value > 0) {
      final fill = RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width * value, size.height), radius);
      canvas.drawRRect(fill, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _StageBarPainter old) =>
      old.value != value ||
      old.rangeLow != rangeLow ||
      old.rangeHigh != rangeHigh;
}

// ─── Line chart (HR / SpO₂) ───────────────────────────────────────────────────

/// Samsung-style overnight line chart: value on Y, time on X, with a dashed
/// average line and an optional dotted reference line (e.g. SpO₂ 90%).
class SleepLineChart extends StatelessWidget {
  final List<SeriesPoint> points;
  final Color color;
  final double? minY;
  final double? maxY;
  final double? average;
  final double? referenceY;
  final String unit;

  const SleepLineChart({
    super.key,
    required this.points,
    required this.color,
    this.minY,
    this.maxY,
    this.average,
    this.referenceY,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      width: double.infinity,
      child: CustomPaint(
        painter: _LineChartPainter(
          points: points,
          color: color,
          minY: minY,
          maxY: maxY,
          average: average,
          referenceY: referenceY,
          unit: unit,
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<SeriesPoint> points;
  final Color color;
  final double? minY;
  final double? maxY;
  final double? average;
  final double? referenceY;
  final String unit;

  _LineChartPainter({
    required this.points,
    required this.color,
    this.minY,
    this.maxY,
    this.average,
    this.referenceY,
    this.unit = '',
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const leftPad = 34.0;
    const bottomPad = 18.0;
    final plotW = size.width - leftPad;
    final plotH = size.height - bottomPad;

    final start = points.first.t;
    final end = points.last.t;
    final totalMs = end.difference(start).inMilliseconds;
    if (totalMs <= 0) return;

    var lo = minY ?? points.map((p) => p.v).reduce((a, b) => a < b ? a : b);
    var hi = maxY ?? points.map((p) => p.v).reduce((a, b) => a > b ? a : b);
    if (referenceY != null) {
      if (referenceY! < lo) lo = referenceY!;
      if (referenceY! > hi) hi = referenceY!;
    }
    if (hi - lo < 1) hi = lo + 1;

    double x(DateTime t) =>
        leftPad + plotW * (t.difference(start).inMilliseconds / totalMs);
    double y(double v) => plotH - plotH * ((v - lo) / (hi - lo));

    // Y gridlines (min / max).
    final gridP = Paint()
      ..color = _grid.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (final v in [lo, hi]) {
      final yy = y(v);
      canvas.drawLine(Offset(leftPad, yy), Offset(size.width, yy), gridP);
      _label(canvas, v.round().toString(), Offset(0, yy - 5),
          align: TextAlign.right, width: leftPad - 6);
    }

    // Optional dotted reference line (e.g. SpO₂ 90%).
    if (referenceY != null) {
      final yy = y(referenceY!);
      _dashedLine(canvas, Offset(leftPad, yy), Offset(size.width, yy),
          Paint()
            ..color = _muted
            ..strokeWidth = 1,
          dash: 2, gap: 4);
      _label(canvas, '${referenceY!.round()}', Offset(0, yy - 5),
          align: TextAlign.right, width: leftPad - 6, color: _muted);
    }

    // The series line.
    final path = Path()..moveTo(x(points.first.t), y(points.first.v));
    for (final p in points.skip(1)) {
      path.lineTo(x(p.t), y(p.v));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);

    // Dashed average line + label.
    if (average != null) {
      final yy = y(average!);
      _dashedLine(canvas, Offset(leftPad, yy), Offset(size.width, yy),
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..strokeWidth = 1,
          dash: 5, gap: 4);
      _label(canvas, 'avg ${average!.round()}$unit',
          Offset(size.width, yy - 12),
          align: TextAlign.right, width: 90, color: color);
    }

    // X time labels.
    for (var i = 0; i <= 3; i++) {
      final t = start.add(Duration(milliseconds: (totalMs * i / 3).round()));
      final align = i == 0
          ? TextAlign.left
          : i == 3
              ? TextAlign.right
              : TextAlign.center;
      _label(canvas, _fmtTime(t), Offset(leftPad + plotW * i / 3, plotH + 4),
          align: align, width: 60);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dash = 4, double gap = 4}) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final p1 = a + dir * d;
      final p2 = a + dir * (d + dash).clamp(0, total);
      canvas.drawLine(p1, p2, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.points != points ||
      old.average != average ||
      old.referenceY != referenceY;
}
