import 'package:flutter/material.dart';

import '../../services/sleep_service.dart';
import '../database/workout_database.dart';
import '../models/sleep_session.dart';
import '../screens/sleep_screen.dart';

const _card = Color(0xFF1A1A2E);
const _border = Color(0xFF1E1E35);
const _muted = Color(0xFF888899);

/// Home-screen card showing last night's sleep: duration, score, and a mini
/// stage bar. Taps through to the full [SleepScreen]. Reads cached data and
/// kicks a background Health Connect sync so it stays fresh.
class SleepCard extends StatefulWidget {
  const SleepCard({super.key});

  @override
  State<SleepCard> createState() => _SleepCardState();
}

class _SleepCardState extends State<SleepCard> {
  SleepSession? _session;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    final s = await WorkoutDatabase.instance.getSleepSession(_today);
    if (mounted) {
      setState(() {
        _session = s;
        _loaded = true;
      });
    }
    // Refresh from Health Connect in the background, then reload.
    final synced = await SleepService.syncNight(DateTime.now());
    if (synced != null && mounted) {
      final s2 = await WorkoutDatabase.instance.getSleepSession(_today);
      if (mounted) setState(() => _session = s2);
    }
  }

  Future<void> _open() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SleepScreen()));
    _load();
  }

  String _dur(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return GestureDetector(
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFB39DFF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.bedtime_rounded,
                  color: Color(0xFFB39DFF), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: _content(s)),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _content(SleepSession? s) {
    if (!_loaded) {
      return const Text('Sleep',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold));
    }
    if (s == null || s.asleepMinutes == 0) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sleep',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 2),
          Text('Tap to track from Health Connect',
              style: TextStyle(color: _muted, fontSize: 12)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_dur(s.asleepMinutes),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (s.score > 0)
              Text('Score ${s.score}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        if (s.hasStages) _miniStageBar(s) else const _SleepLabel(),
      ],
    );
  }

  Widget _miniStageBar(SleepSession s) {
    final total = s.awakeMinutes + s.remMinutes + s.lightMinutes + s.deepMinutes;
    if (total == 0) return const _SleepLabel();
    Widget seg(int m, Color c) =>
        m == 0 ? const SizedBox.shrink() : Expanded(flex: m, child: Container(color: c));
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            seg(s.deepMinutes, const Color(0xFF4834D4)),
            seg(s.lightMinutes, const Color(0xFF7C6FF0)),
            seg(s.remMinutes, const Color(0xFFB39DFF)),
            seg(s.awakeMinutes, const Color(0xFFE84393)),
          ],
        ),
      ),
    );
  }
}

class _SleepLabel extends StatelessWidget {
  const _SleepLabel();
  @override
  Widget build(BuildContext context) => const Text('Last night',
      style: TextStyle(color: _muted, fontSize: 12));
}
