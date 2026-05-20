import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../database/workout_database.dart';

class MonthlySummaryScreen extends StatefulWidget {
  final int year;
  final int month;

  const MonthlySummaryScreen({
    super.key,
    required this.year,
    required this.month,
  });

  @override
  State<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends State<MonthlySummaryScreen> {
  static const _monthNames = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await WorkoutDatabase.instance
        .getMonthlySummary(widget.year, widget.month);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  String get _monthLabel => _monthNames[widget.month];

  String _fmtVolume(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}k kg';
    }
    return '${v.toStringAsFixed(0)} kg';
  }

  String _volDelta(double cur, double prev) {
    if (prev == 0) return '';
    final pct = ((cur - prev) / prev * 100).round();
    return pct >= 0 ? '+$pct%' : '$pct%';
  }

  String _fmtOrm(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(1)} kg';

  void _share() {
    if (_data == null) return;
    final d = _data!;
    final sessions = d['total_sessions'] as int;
    final volume = (d['total_volume'] as double);
    final prev = (d['prev_volume'] as double);
    final streak = d['longest_streak'] as int;
    final muscle = d['top_muscle_group'] as String?;
    final bwFirst = d['bw_first'] as double?;
    final bwLast = d['bw_last'] as double?;
    final prs = (d['top_prs'] as List).cast<Map<String, dynamic>>();

    final sb = StringBuffer();
    sb.writeln('🏋️ $_monthLabel ${widget.year} — Month in Review');
    sb.writeln('━━━━━━━━━━━━━━━━━━━━━━━━');
    sb.writeln('Sessions: $sessions');
    final delta = _volDelta(volume, prev);
    sb.writeln(
        'Volume: ${_fmtVolume(volume)}${delta.isNotEmpty ? ' ($delta vs last month)' : ''}');
    sb.writeln('Longest streak: $streak day${streak == 1 ? '' : 's'}');
    if (muscle != null) sb.writeln('Top muscle: $muscle');
    if (prs.isNotEmpty) {
      sb.writeln('\n🏆 PRs set:');
      for (final pr in prs) {
        final old = pr['old_1rm'] as double?;
        final nw = pr['new_1rm'] as double;
        sb.writeln(
            '• ${pr['name']}: ${_fmtOrm(old)} → ${_fmtOrm(nw)} est. 1RM');
      }
    }
    if (bwFirst != null && bwLast != null) {
      final change = bwLast - bwFirst;
      final sign = change >= 0 ? '+' : '';
      sb.writeln('\nWeight: ${bwFirst.toStringAsFixed(1)} → '
          '${bwLast.toStringAsFixed(1)} kg ($sign${change.toStringAsFixed(1)} kg)');
    }
    sb.writeln('\n📱 Tracked with Aawara');

    Share.share(sb.toString(),
        subject: '$_monthLabel ${widget.year} — My Month in Review');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_monthLabel ${widget.year}',
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const Text(
              'Your Month in Review',
              style: TextStyle(color: Color(0xFF888899), fontSize: 12),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _buildBody(),
      bottomNavigationBar: _data != null && !_loading
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: ElevatedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Share Summary',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    final d = _data!;
    final sessions = d['total_sessions'] as int;
    final volume = (d['total_volume'] as double);
    final prev = (d['prev_volume'] as double);
    final streak = d['longest_streak'] as int;
    final muscle = d['top_muscle_group'] as String?;
    final bwFirst = d['bw_first'] as double?;
    final bwLast = d['bw_last'] as double?;
    final prs = (d['top_prs'] as List).cast<Map<String, dynamic>>();

    final delta = _volDelta(volume, prev);
    final deltaPositive =
        prev > 0 && volume >= prev;

    if (sessions == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.calendar_month_rounded,
                    color: Color(0xFFFFD700), size: 36),
              ),
              const SizedBox(height: 16),
              const Text('No workouts logged',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Complete a workout in $_monthLabel to see your summary.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        // ── Key stats ───────────────────────────────────────────────────
        _goldHeader('Key Stats'),
        _card(
          child: Row(
            children: [
              _statPill(Icons.fitness_center_rounded, '$sessions',
                  'Session${sessions == 1 ? '' : 's'}'),
              _vertDiv(),
              _statPill(Icons.local_fire_department_rounded, '$streak',
                  'Day streak'),
              if (muscle != null) ...[
                _vertDiv(),
                _statPill(Icons.emoji_events_rounded, muscle, 'Top muscle'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Volume ──────────────────────────────────────────────────────
        _goldHeader('Volume Lifted'),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmtVolume(volume),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                  if (delta.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (deltaPositive
                                ? const Color(0xFF2ECC71)
                                : const Color(0xFFE74C3C))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        delta,
                        style: TextStyle(
                            color: deltaPositive
                                ? const Color(0xFF2ECC71)
                                : const Color(0xFFE74C3C),
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
              if (prev > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'vs ${_fmtVolume(prev)} last month',
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── PRs ─────────────────────────────────────────────────────────
        if (prs.isNotEmpty) ...[
          _goldHeader('Personal Records'),
          _card(
            child: Column(
              children: [
                for (int i = 0; i < prs.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: Color(0xFF1E1E35)),
                  _prRow(prs[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Body weight ─────────────────────────────────────────────────
        if (bwFirst != null && bwLast != null) ...[
          _goldHeader('Body Weight'),
          _card(
            child: Row(
              children: [
                _weightCol('Start', bwFirst),
                const Icon(Icons.arrow_forward_rounded,
                    color: Color(0xFF555577), size: 20),
                _weightCol('End', bwLast),
                const Spacer(),
                _weightDeltaChip(bwFirst, bwLast),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _goldHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: child,
    );
  }

  Widget _statPill(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFFFD700), size: 22),
          const SizedBox(height: 6),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Color(0xFF888899), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _vertDiv() => Container(
        width: 1,
        height: 50,
        color: const Color(0xFF1E1E35),
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

  Widget _prRow(Map<String, dynamic> pr) {
    final old1rm = pr['old_1rm'] as double?;
    final new1rm = pr['new_1rm'] as double;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Text('⭐', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(pr['name'] as String,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ),
          Text(
            '${_fmtOrm(old1rm)} → ${_fmtOrm(new1rm)}',
            style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _weightCol(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Text('${value.toStringAsFixed(1)} kg',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF888899), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _weightDeltaChip(double first, double last) {
    final change = last - first;
    final isPos = change > 0;
    final label =
        '${isPos ? '+' : ''}${change.toStringAsFixed(1)} kg';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isPos ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: isPos
                ? const Color(0xFFE74C3C)
                : const Color(0xFF2ECC71),
            fontSize: 13,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}
