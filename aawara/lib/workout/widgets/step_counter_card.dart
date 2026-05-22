import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/step_tracking_service.dart';
import '../../utils/safe_navigation.dart';
import '../screens/step_goal_screen.dart';

class StepCounterCard extends StatefulWidget {
  const StepCounterCard({super.key});

  @override
  State<StepCounterCard> createState() => _StepCounterCardState();
}

class _StepCounterCardState extends State<StepCounterCard> {
  bool _enabled = false;
  int _steps = 0;
  int _goal = 8000;
  bool _goalJustReached = false;
  bool _refreshing = false;
  int _manualSteps = 0;
  StreamSubscription<StepUpdate>? _sub;
  Timer? _goalBannerTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _goalBannerTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final enabled = await StepTrackingService.isEnabled();
    if (!mounted) return;
    setState(() => _enabled = enabled);
    if (!enabled) return;

    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('step_goal') ?? 8000;
    final steps = await StepTrackingService.getTodaySteps();
    final manualSteps = await StepTrackingService.getManualStepsAdded();
    if (!mounted) return;
    setState(() {
      _goal = goal;
      _steps = steps;
      _manualSteps = manualSteps;
    });

    _sub = StepTrackingService.stepStream.listen((update) {
      if (!mounted) return;
      final prevSteps = _steps;
      setState(() {
        _steps = update.steps;
        _goal = update.goal;
      });
      if (prevSteps < update.goal && update.steps >= update.goal) {
        _triggerGoalReached();
      }
    });
  }

  void _triggerGoalReached() {
    HapticFeedback.lightImpact();
    setState(() => _goalJustReached = true);
    _goalBannerTimer?.cancel();
    _goalBannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _goalJustReached = false);
    });
  }

  Future<void> _enable() async {
    final enabled = await StepTrackingService.enable();
    if (!mounted) return;
    if (enabled) {
      setState(() => _enabled = true);
      _init();
    }
  }

  Future<void> _changeGoal() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
          builder: (_) => const StepGoalScreen(isFirstSetup: false)),
    );
    if (result != null && mounted) {
      setState(() => _goal = result);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await StepTrackingService.refreshStream();
    final steps = await StepTrackingService.getTodaySteps();
    final manual = await StepTrackingService.getManualStepsAdded();
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('step_goal') ?? 8000;
    if (mounted) {
      setState(() {
        _steps = steps;
        _goal = goal;
        _manualSteps = manual;
        _refreshing = false;
      });
    }
  }

  Future<void> _addStepsManually() async {
    final ctrl = TextEditingController();
    final added = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Add Steps',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Steps walked without your phone',
              style: TextStyle(color: Color(0xFF888899), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 32,
                  fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '0',
                hintStyle: TextStyle(color: Color(0xFF444466)),
              ),
            ),
            if (_manualSteps > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Already added today: ${_formatSteps(_manualSteps)} steps',
                  style: const TextStyle(
                      color: Color(0xFF555577), fontSize: 12),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => popAfterFocusSettles(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              popAfterFocusSettles(ctx, v);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Add',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (added != null && added > 0) {
      await StepTrackingService.addManualSteps(added);
      final steps = await StepTrackingService.getTodaySteps();
      final manual = await StepTrackingService.getManualStepsAdded();
      if (mounted) setState(() { _steps = steps; _manualSteps = manual; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: _enabled ? _buildActive() : _buildDisabled(),
    );
  }

  Widget _buildDisabled() {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF555577).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.directions_walk_rounded,
              color: Color(0xFF555577), size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Step tracking is off',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              Text('Enable it to count your daily steps',
                  style: TextStyle(color: Color(0xFF555577), fontSize: 12)),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: _enable,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child:
              const Text('Enable', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildActive() {
    final progress = (_goal > 0 ? _steps / _goal : 0.0).clamp(0.0, 1.0);
    final isGold = _steps >= _goal;
    final dist = (_steps * 0.000762).toStringAsFixed(1);
    final cal = (_steps * 0.038).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.directions_walk_rounded,
                color: Color(0xFF888899), size: 18),
            const SizedBox(width: 6),
            const Text('Steps',
                style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
            const Spacer(),
            GestureDetector(
              onTap: _addStepsManually,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _manualSteps > 0
                      ? const Color(0xFFFFD700).withValues(alpha: 0.10)
                      : const Color(0xFF2A2A45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  color: _manualSteps > 0
                      ? const Color(0xFFFFD700)
                      : const Color(0xFFAAAAAA),
                  size: 15,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _refresh,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _refreshing
                      ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                      : const Color(0xFF2A2A45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AnimatedRotation(
                  turns: _refreshing ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: _refreshing
                        ? const Color(0xFFFFD700)
                        : const Color(0xFFAAAAAA),
                    size: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    _formatSteps(_steps),
                    key: ValueKey(_steps),
                    style: TextStyle(
                      color: isGold
                          ? const Color(0xFFFFD700)
                          : Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '/ ${_formatSteps(_goal)}',
                  style: const TextStyle(
                      color: Color(0xFF555577), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _goalJustReached
              ? const Text(
                  'Goal reached!',
                  key: ValueKey('goal'),
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                )
              : Row(
                  key: const ValueKey('stats'),
                  children: [
                    Text('~$dist km',
                        style: const TextStyle(
                            color: Color(0xFF555577), fontSize: 12)),
                    const Text('  ·  ',
                        style: TextStyle(
                            color: Color(0xFF333355), fontSize: 12)),
                    Text('~$cal kcal',
                        style: const TextStyle(
                            color: Color(0xFF555577), fontSize: 12)),
                    if (_manualSteps > 0) ...[
                      const Text('  ·  ',
                          style: TextStyle(
                              color: Color(0xFF333355), fontSize: 12)),
                      Text('+${_formatSteps(_manualSteps)} manual',
                          style: const TextStyle(
                              color: Color(0xFFFFD700), fontSize: 11)),
                    ],
                    const Spacer(),
                    GestureDetector(
                      onTap: _changeGoal,
                      child: const Text('Change goal ›',
                          style: TextStyle(
                              color: Color(0xFF555577), fontSize: 12)),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  String _formatSteps(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
