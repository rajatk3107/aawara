import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/sleep_series.dart';

const _muted = Color(0xFF888899);
const _grid = Color(0xFF2A2A45);
const _red = Color(0xFFE74C3C);

/// HR line chart for a completed watch workout: a bpm y-axis with round
/// gridlines, a gradient fill, a dashed average line, and a marked peak — with
/// a legend so the average is readable off the busy line. Times are local.
class WorkoutHrChart extends StatelessWidget {
  final List<SeriesPoint> points;
  final double average;
  const WorkoutHrChart(
      {super.key, required this.points, required this.average});

  @override
  Widget build(BuildContext context) {
    final peak = points.map((p) => p.v).reduce((a, b) => a > b ? a : b).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legendDash(),
            const SizedBox(width: 5),
            Text('avg ${average.round()}',
                style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(width: 16),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('peak $peak',
                style: const TextStyle(
                    color: _red, fontSize: 11, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Text('bpm', style: TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 132,
          width: double.infinity,
          child: CustomPaint(
            painter: _HrChartPainter(points: points, average: average),
          ),
        ),
      ],
    );
  }

  Widget _legendDash() => SizedBox(
        width: 16,
        height: 2,
        child: CustomPaint(painter: _DashSwatch()),
      );
}

class _DashSwatch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _muted
      ..strokeWidth = 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + 4, 1), p);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HrChartPainter extends CustomPainter {
  final List<SeriesPoint> points;
  final double average;
  _HrChartPainter({required this.points, required this.average});

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

    var dataLo = points.map((p) => p.v).reduce((a, b) => a < b ? a : b);
    var dataHi = points.map((p) => p.v).reduce((a, b) => a > b ? a : b);
    final pad = ((dataHi - dataLo) * 0.08).clamp(3.0, 15.0);
    final lo = dataLo - pad;
    final hi = dataHi + pad;
    final span = (hi - lo) < 1 ? 1 : (hi - lo);

    double x(DateTime t) =>
        leftPad + plotW * (t.difference(start).inMilliseconds / totalMs);
    double y(double v) => plotH - plotH * ((v - lo) / span);

    // Round bpm gridlines (multiples of 30) that fall inside the range.
    final gridP = Paint()
      ..color = _grid.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    for (var g = (lo / 30).ceil() * 30; g <= hi; g += 30) {
      final yy = y(g.toDouble());
      canvas.drawLine(Offset(leftPad, yy), Offset(size.width, yy), gridP);
      _label(canvas, '$g', Offset(leftPad - 6, yy - 6), align: TextAlign.right);
    }

    // Gradient fill under the line.
    final fill = Path()..moveTo(x(points.first.t), plotH);
    for (final p in points) {
      fill.lineTo(x(p.t), y(p.v));
    }
    fill.lineTo(x(points.last.t), plotH);
    fill.close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(0, plotH),
            [_red.withValues(alpha: 0.28), _red.withValues(alpha: 0.0)],
          ));

    // The HR line.
    final line = Path()..moveTo(x(points.first.t), y(points.first.v));
    for (final p in points.skip(1)) {
      line.lineTo(x(p.t), y(p.v));
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = _red
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);

    // Dashed average line (muted so it reads against the red line).
    final ay = y(average);
    _dashedLine(canvas, Offset(leftPad, ay), Offset(size.width, ay),
        Paint()
          ..color = _muted
          ..strokeWidth = 1);

    // Peak marker.
    final peak = points.reduce((a, b) => a.v >= b.v ? a : b);
    final pc = Offset(x(peak.t), y(peak.v));
    canvas.drawCircle(pc, 4.5, Paint()..color = _red);
    canvas.drawCircle(
        pc,
        4.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // X time labels (local).
    for (var i = 0; i <= 3; i++) {
      final t = start.add(Duration(milliseconds: (totalMs * i / 3).round()));
      final align = i == 0
          ? TextAlign.left
          : i == 3
              ? TextAlign.right
              : TextAlign.center;
      _label(canvas, _fmtTime(t), Offset(leftPad + plotW * i / 3, plotH + 4),
          align: align);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final p1 = a + dir * d;
      final p2 = a + dir * (d + 5).clamp(0, total);
      canvas.drawLine(p1, p2, paint);
      d += 9;
    }
  }

  void _label(Canvas canvas, String text, Offset at,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text, style: const TextStyle(color: _muted, fontSize: 10)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 64);
    var dx = at.dx;
    if (align == TextAlign.right) dx = at.dx - tp.width;
    if (align == TextAlign.center) dx = at.dx - tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  static String _fmtTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }

  @override
  bool shouldRepaint(covariant _HrChartPainter old) =>
      old.points != points || old.average != average;
}
