import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/sleep_service.dart';
import '../database/workout_database.dart';
import '../models/sleep_session.dart';
import '../utils/sleep_metrics.dart';

const _bg = Color(0xFF0D0D1A);
const _card = Color(0xFF1A1A2E);
const _border = Color(0xFF1E1E35);
const _muted = Color(0xFF888899);
const _gold = Color(0xFFFFD700);

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

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});

  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final _db = WorkoutDatabase.instance;

  DateTime _date = DateTime.now();
  SleepSession? _session;
  List<SleepSession> _week = [];
  bool _loading = true;
  bool _syncing = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  String _ds(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get _isToday => _ds(_date) == _ds(DateTime.now());

  Future<void> _init() async {
    _hasPermission = await SleepService.hasPermission();
    await _loadFromDb();
    if (_hasPermission) {
      // Recompute cached nights (picks up score/calibration changes via the
      // bumped backfill flag), then refresh the list.
      SleepService.syncHistory().then((_) {
        if (mounted) _loadFromDb();
      });
    }
    // Refresh the visible night from Health Connect in the background.
    _syncCurrent();
  }

  Future<void> _loadFromDb() async {
    final weekStart = _date.subtract(const Duration(days: 6));
    final results = await Future.wait([
      _db.getSleepSession(_ds(_date)),
      _db.getSleepSessions(_ds(weekStart), _ds(_date)),
    ]);
    if (!mounted) return;
    setState(() {
      _session = results[0] as SleepSession?;
      _week = results[1] as List<SleepSession>;
      _loading = false;
    });
  }

  Future<void> _syncCurrent() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    await SleepService.syncNight(_date);
    if (!mounted) return;
    _hasPermission = await SleepService.hasPermission();
    await _loadFromDb();
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _connect() async {
    final granted = await SleepService.requestPermission();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    if (granted) {
      setState(() => _loading = true);
      await SleepService.syncHistory();
      await _loadFromDb();
    }
  }

  void _changeDay(int delta) {
    final next = _date.add(Duration(days: delta));
    if (next.isAfter(DateTime.now())) return;
    setState(() {
      _date = next;
      _loading = true;
    });
    _loadFromDb();
    _syncCurrent();
  }

  Future<void> _addManually() async {
    final hours = await _askHours();
    if (hours == null) return;
    final mins = (hours * 60).round();
    // Manual entry only has total hours — estimate typical stage proportions and
    // assume neutral/optimal values for the factors we can't know, so the score
    // is essentially duration-driven.
    final score = computeSleepScore(
      actualSleepMinutes: mins.toDouble(),
      deepSleepMinutes: mins * 0.15,
      remSleepMinutes: mins * 0.22,
      awakeMinutes: 20,
      latencyMinutes: 12,
      bedtime: DateTime(_date.year, _date.month, _date.day - 1, 22, 30),
      avgHrBpm: 60,
      spo2DipMinutes: 0,
    );
    final session = SleepSession(
      date: _ds(_date),
      totalMinutes: mins,
      asleepMinutes: mins,
      score: score,
      source: 'manual',
    );
    await _db.upsertSleepSession(session);
    await _db.setWellnessSleepHours(_ds(_date), hours);
    await _loadFromDb();
  }

  Future<double?> _askHours() async {
    final ctrl = TextEditingController(
        text: _session != null
            ? (_session!.asleepMinutes / 60).toStringAsFixed(1)
            : '7.5');
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sleep hours',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(color: Colors.white, fontSize: 22),
          decoration: const InputDecoration(
            suffixText: 'hours',
            suffixStyle: TextStyle(color: _muted),
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            style: ElevatedButton.styleFrom(
                backgroundColor: _gold, foregroundColor: Colors.black, elevation: 0),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Sleep',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _gold)),
              ),
            )
          else
            IconButton(
                icon: const Icon(Icons.refresh_rounded, color: _gold),
                onPressed: _syncCurrent),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _dateNav(),
                const SizedBox(height: 16),
                if (!_hasPermission && _session == null) _permissionCard(),
                if (_session != null) ...[
                  _scoreHeader(_session!),
                  const SizedBox(height: 16),
                  if (_session!.hasStages) ...[
                    _hypnogramCard(_session!),
                    const SizedBox(height: 16),
                    _stageBreakdown(_session!),
                    const SizedBox(height: 16),
                  ],
                  if (_hasVitals(_session!)) ...[
                    _vitalsCard(_session!),
                    const SizedBox(height: 16),
                  ],
                ] else if (_hasPermission) ...[
                  _noDataCard(),
                ],
                if (_week.any((s) => s.asleepMinutes > 0)) _weekTrend(),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _addManually,
                    icon: const Icon(Icons.edit_rounded, size: 16, color: _muted),
                    label: Text(
                        _session?.source == 'manual'
                            ? 'Edit hours manually'
                            : 'Add hours manually',
                        style: const TextStyle(color: _muted)),
                  ),
                ),
              ],
            ),
    );
  }

  bool _hasVitals(SleepSession s) =>
      s.hrAvg != null || s.spo2Avg != null || s.respAvg != null;

  Widget _dateNav() {
    final label = _isToday
        ? 'Last night'
        : _ds(_date) ==
                _ds(DateTime.now().subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : _prettyDate(_date);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _navBtn(Icons.chevron_left_rounded, () => _changeDay(-1)),
        Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        Opacity(
          opacity: _isToday ? 0.3 : 1,
          child: _navBtn(
              Icons.chevron_right_rounded, _isToday ? null : () => _changeDay(1)),
        ),
      ],
    );
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: _card, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      );

  String _prettyDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _dur(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _permissionCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const Icon(Icons.bedtime_rounded, color: _remColor, size: 40),
          const SizedBox(height: 12),
          const Text('Connect Health Connect',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            'Grant sleep access to pull your sleep stages and vitals from your watch automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _connect,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text('Connect',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noDataCard() => Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: const Column(
          children: [
            Icon(Icons.nightlight_round, color: _muted, size: 36),
            SizedBox(height: 12),
            Text('No sleep recorded for this night',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Wear your watch to bed, or add hours manually below.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      );

  Widget _scoreHeader(SleepSession s) {
    final scoreColor = s.score >= 80
        ? const Color(0xFF2ECC71)
        : s.score >= 60
            ? _gold
            : const Color(0xFFE67E22);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${s.score}',
                      style: TextStyle(
                          color: scoreColor,
                          fontSize: 44,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('/100',
                        style: TextStyle(color: _muted, fontSize: 15)),
                  ),
                ],
              ),
              Text('SLEEP SCORE · ${sleepScoreLabel(s.score).toUpperCase()}',
                  style: TextStyle(
                      color: scoreColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_dur(s.asleepMinutes),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const Text('time asleep',
                  style: TextStyle(color: _muted, fontSize: 12)),
              if (s.startIso != null && s.endIso != null) ...[
                const SizedBox(height: 6),
                Text(_timeRange(s),
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _timeRange(SleepSession s) {
    String fmt(String iso) {
      final d = DateTime.parse(iso);
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final ap = d.hour < 12 ? 'am' : 'pm';
      return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
    }

    return '${fmt(s.startIso!)} – ${fmt(s.endIso!)}';
  }

  List<SleepStageSegment> _parseStages(SleepSession s) {
    if (s.stagesJson == null) return [];
    try {
      final list = jsonDecode(s.stagesJson!) as List;
      return [
        for (final e in list)
          SleepStageSegment(
            SleepStage.values.firstWhere((v) => v.name == e['stage']),
            DateTime.parse(e['start'] as String),
            DateTime.parse(e['end'] as String),
          )
      ];
    } catch (_) {
      return [];
    }
  }

  Widget _hypnogramCard(SleepSession s) {
    final segments = _parseStages(s);
    if (segments.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SLEEP STAGES',
              style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(painter: _HypnogramPainter(segments)),
          ),
        ],
      ),
    );
  }

  Widget _stageBreakdown(SleepSession s) {
    final asleep = s.asleepMinutes == 0 ? 1 : s.asleepMinutes;
    Widget row(String label, int minutes, Color color, {int? ofTotal}) {
      final denom = ofTotal ?? asleep;
      final pct = denom == 0 ? 0.0 : minutes / denom;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${(pct * 100).round()}%   ${_dur(minutes)}',
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: _bg,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      );
    }

    final total = s.totalMinutes == 0 ? s.asleepMinutes : s.totalMinutes;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          row('Awake', s.awakeMinutes, _awakeColor, ofTotal: total),
          row('REM', s.remMinutes, _remColor),
          row('Light', s.lightMinutes, _lightColor),
          row('Deep', s.deepMinutes, _deepColor),
        ],
      ),
    );
  }

  Widget _vitalsCard(SleepSession s) {
    final items = <Widget>[];
    if (s.hrAvg != null) {
      final rest = s.hrMin != null ? ' · ${s.hrMin!.round()} rest' : '';
      items.add(_vital('Heart rate', '${s.hrAvg!.round()}', 'avg bpm$rest',
          Icons.favorite_rounded, const Color(0xFFE74C3C)));
    }
    if (s.spo2Avg != null) {
      items.add(_vital('Blood oxygen', '${s.spo2Avg!.round()}%', 'avg SpO₂',
          Icons.air_rounded, const Color(0xFF3498DB)));
    }
    if (s.respAvg != null) {
      items.add(_vital('Respiratory', s.respAvg!.toStringAsFixed(1), '/min',
          Icons.waves_rounded, const Color(0xFF1ABC9C)));
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items,
      ),
    );
  }

  Widget _vital(
      String label, String value, String unit, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(unit, style: const TextStyle(color: _muted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    );
  }

  Widget _weekTrend() {
    final byDate = {for (final s in _week) s.date: s};
    final days = List.generate(7, (i) {
      final d = _date.subtract(Duration(days: 6 - i));
      return (d, byDate[_ds(d)]);
    });
    final maxMin = days.fold<int>(
        1, (m, e) => (e.$2?.asleepMinutes ?? 0) > m ? e.$2!.asleepMinutes : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LAST 7 DAYS',
              style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (d, s) in days)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          s != null && s.asleepMinutes > 0
                              ? (s.asleepMinutes / 60).toStringAsFixed(1)
                              : '',
                          style: const TextStyle(color: _muted, fontSize: 9),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 14,
                          height: (80 *
                                  ((s?.asleepMinutes ?? 0) / maxMin))
                              .clamp(2.0, 80.0),
                          decoration: BoxDecoration(
                            color: _ds(d) == _ds(_date) ? _gold : _lightColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_weekday(d),
                            style: const TextStyle(color: _muted, fontSize: 10)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _weekday(DateTime d) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

class _HypnogramPainter extends CustomPainter {
  final List<SleepStageSegment> segments;
  _HypnogramPainter(this.segments);

  // Higher row = lighter stage. Awake at top, Deep at bottom.
  static const _rowOf = {
    SleepStage.awake: 0,
    SleepStage.rem: 1,
    SleepStage.light: 2,
    SleepStage.deep: 3,
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    final start = segments.first.start;
    final end = segments.last.end;
    final totalMs = end.difference(start).inMilliseconds;
    if (totalMs <= 0) return;

    const rows = 4;
    final rowH = size.height / rows;
    final barH = rowH * 0.55;

    double x(DateTime t) =>
        size.width * (t.difference(start).inMilliseconds / totalMs);

    final paint = Paint()..style = PaintingStyle.fill;
    for (final seg in segments) {
      final row = _rowOf[seg.stage]!;
      final left = x(seg.start);
      final right = x(seg.end);
      final top = row * rowH + (rowH - barH) / 2;
      paint.color = _stageColor(seg.stage);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, top, right < left + 1 ? left + 1 : right, top + barH),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HypnogramPainter old) =>
      old.segments != segments;
}
