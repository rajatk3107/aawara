import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';

class WaterTrackerCard extends StatefulWidget {
  final String date;
  const WaterTrackerCard({super.key, required this.date});

  @override
  State<WaterTrackerCard> createState() => _WaterTrackerCardState();
}

class _WaterTrackerCardState extends State<WaterTrackerCard> {
  final _db = WorkoutDatabase.instance;
  WaterLog _log = const WaterLog(date: '', glassesDrunk: 0, targetGlasses: 8);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WaterTrackerCard old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final log = await _db.getWaterLog(widget.date);
    if (mounted) setState(() { _log = log; _loading = false; });
  }

  Future<void> _add() async {
    if (_log.glassesDrunk >= _log.targetGlasses + 4) return;
    HapticFeedback.lightImpact();
    final next = _log.copyWith(glassesDrunk: _log.glassesDrunk + 1);
    setState(() => _log = next);
    await _db.setWaterGlasses(
        widget.date, next.glassesDrunk,
        targetGlasses: next.targetGlasses);
  }

  Future<void> _remove() async {
    if (_log.glassesDrunk <= 0) return;
    HapticFeedback.lightImpact();
    final next = _log.copyWith(glassesDrunk: _log.glassesDrunk - 1);
    setState(() => _log = next);
    await _db.setWaterGlasses(
        widget.date, next.glassesDrunk,
        targetGlasses: next.targetGlasses);
  }

  void _editTarget() {
    final ctrl =
        TextEditingController(text: _log.targetGlasses.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Daily Water Target',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  color: Color(0xFF3BAFDA),
                  fontSize: 28,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '8',
                  hintStyle: TextStyle(color: Color(0xFF444466))),
            ),
            const Text('glasses (250 ml each)',
                style: TextStyle(color: Color(0xFF555577), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888899))),
          ),
          ElevatedButton(
            onPressed: () async {
              final v = int.tryParse(ctrl.text);
              Navigator.pop(ctx);
              if (v != null && v > 0 && v <= 30) {
                await _db.updateWaterTarget(widget.date, v);
                _load();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3BAFDA),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Set',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF3BAFDA)),
          ),
        ),
      );
    }

    final glasses = _log.glassesDrunk;
    final target = _log.targetGlasses;
    final pct = target > 0 ? (glasses / target).clamp(0.0, 1.0) : 0.0;
    final done = glasses >= target;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? const Color(0xFF3BAFDA).withValues(alpha: 0.4)
              : const Color(0xFF1E1E35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Text('💧', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Text('Water',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: _editTarget,
                child: Row(
                  children: [
                    Text(
                      '${glasses} / $target glasses',
                      style: TextStyle(
                          color: done
                              ? const Color(0xFF3BAFDA)
                              : const Color(0xFF888899),
                          fontSize: 13,
                          fontWeight:
                              done ? FontWeight.bold : FontWeight.normal),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined,
                        color: Color(0xFF333355), size: 13),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Glass dots + buttons
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: List.generate(target, (i) {
                    final filled = i < glasses;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: filled
                            ? const Color(0xFF3BAFDA)
                            : const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: filled
                              ? const Color(0xFF3BAFDA)
                              : const Color(0xFF1E1E35),
                        ),
                      ),
                      child: filled
                          ? const Icon(Icons.water_drop_rounded,
                              color: Colors.white, size: 12)
                          : null,
                    );
                  }),
                ),
              ),
              const SizedBox(width: 10),
              // Controls
              Row(
                children: [
                  _controlBtn(
                    Icons.remove_rounded,
                    glasses > 0 ? _remove : null,
                  ),
                  const SizedBox(width: 8),
                  _controlBtn(
                    Icons.add_rounded,
                    _add,
                    highlight: true,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress bar + litre label
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF0D0D1A),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      done
                          ? const Color(0xFF3BAFDA)
                          : const Color(0xFF3BAFDA).withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_log.liters.toStringAsFixed(2)}L / ${_log.targetLiters.toStringAsFixed(1)}L',
                style: const TextStyle(
                    color: Color(0xFF555577), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlBtn(IconData icon, VoidCallback? onTap,
      {bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFF3BAFDA).withValues(alpha: 0.15)
              : const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: highlight
                ? const Color(0xFF3BAFDA).withValues(alpha: 0.4)
                : const Color(0xFF1E1E35),
          ),
        ),
        child: Icon(icon,
            color: onTap == null
                ? const Color(0xFF333355)
                : highlight
                    ? const Color(0xFF3BAFDA)
                    : const Color(0xFF888899),
            size: 18),
      ),
    );
  }
}
