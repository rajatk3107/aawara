import 'package:flutter/material.dart';
import '../database/workout_database.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  Map<String, String> _unlocked = {};
  bool _loading = true;

  static final _achievements = [
    _Achievement(
      id: 'first_rep',
      emoji: '🏋️',
      name: 'First Rep',
      description: 'Complete your first workout',
      lockedDesc: 'Log your first workout to unlock',
    ),
    _Achievement(
      id: 'week_warrior',
      emoji: '🔥',
      name: 'Week Warrior',
      description: '7-day workout streak',
      lockedDesc: 'Maintain a 7-day streak',
    ),
    _Achievement(
      id: 'century_club',
      emoji: '💯',
      name: 'Century Club',
      description: '100 total workouts logged',
      lockedDesc: 'Log 100 workouts',
    ),
    _Achievement(
      id: 'ten_k_club',
      emoji: '🏆',
      name: '10K Club',
      description: '10,000 kg total volume lifted',
      lockedDesc: 'Lift 10,000 kg total',
    ),
    _Achievement(
      id: 'pr_machine',
      emoji: '⭐',
      name: 'PR Machine',
      description: 'Set personal records in 10 exercises',
      lockedDesc: 'Set PRs in 10 different exercises',
    ),
    _Achievement(
      id: 'consistent',
      emoji: '📅',
      name: 'Consistent',
      description: 'Work out 3×/week for 4 weeks straight',
      lockedDesc: 'Train 3+ times a week for 4 consecutive weeks',
    ),
    _Achievement(
      id: 'leg_day_hero',
      emoji: '🦵',
      name: 'Leg Day Hero',
      description: 'Complete 20 workouts with leg exercises',
      lockedDesc: 'Complete 20 sessions that include leg exercises',
    ),
    _Achievement(
      id: 'note_taker',
      emoji: '📓',
      name: 'Note Taker',
      description: 'Write 10 workout notes',
      lockedDesc: 'Add notes to 10 completed workouts',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final unlocked = await WorkoutDatabase.instance.getUnlockedAchievements();
    if (mounted) setState(() { _unlocked = unlocked; _loading = false; });
  }

  int get _unlockedCount =>
      _achievements.where((a) => _unlocked.containsKey(a.id)).length;

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
        title: const Text(
          'Achievements',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Progress header
        _buildProgressHeader(),
        const SizedBox(height: 20),
        // Unlocked first, then locked
        ...(_achievements
          ..sort((a, b) {
            final aUnlocked = _unlocked.containsKey(a.id);
            final bUnlocked = _unlocked.containsKey(b.id);
            if (aUnlocked && !bUnlocked) return -1;
            if (!aUnlocked && bUnlocked) return 1;
            return 0;
          })).map(_buildBadge),
      ],
    );
  }

  Widget _buildProgressHeader() {
    final total = _achievements.length;
    final done = _unlockedCount;
    final pct = total > 0 ? done / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$done / $total Unlocked',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${(pct * 100).round()}%',
                style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: const Color(0xFF0D0D1A),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(_Achievement a) {
    final isUnlocked = _unlocked.containsKey(a.id);
    final date = _unlocked[a.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUnlocked
              ? const Color(0xFFFFD700).withValues(alpha: 0.35)
              : const Color(0xFF1E1E35),
        ),
      ),
      child: Row(
        children: [
          // Emoji badge
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isUnlocked
                  ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                  : const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: ColorFiltered(
                colorFilter: isUnlocked
                    ? const ColorFilter.mode(
                        Colors.transparent, BlendMode.multiply)
                    : const ColorFilter.matrix(<double>[
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                child: Text(a.emoji,
                    style: const TextStyle(fontSize: 28)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  style: TextStyle(
                      color: isUnlocked
                          ? Colors.white
                          : const Color(0xFF555577),
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  isUnlocked ? a.description : a.lockedDesc,
                  style: TextStyle(
                      color: isUnlocked
                          ? const Color(0xFF888899)
                          : const Color(0xFF444466),
                      fontSize: 12),
                ),
                if (isUnlocked && date != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Unlocked $date',
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          // Lock icon for locked
          if (!isUnlocked)
            const Icon(Icons.lock_outline_rounded,
                color: Color(0xFF444466), size: 18),
        ],
      ),
    );
  }
}

class _Achievement {
  final String id;
  final String emoji;
  final String name;
  final String description;
  final String lockedDesc;

  const _Achievement({
    required this.id,
    required this.emoji,
    required this.name,
    required this.description,
    required this.lockedDesc,
  });
}

// ─── Achievement unlock celebration overlay ───────────────────────────────────

class AchievementCelebrationDialog extends StatefulWidget {
  final String emoji;
  final String name;

  const AchievementCelebrationDialog({
    super.key,
    required this.emoji,
    required this.name,
  });

  @override
  State<AchievementCelebrationDialog> createState() =>
      _AchievementCelebrationDialogState();
}

class _AchievementCelebrationDialogState
    extends State<AchievementCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD700), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 14),
              const Text(
                'Achievement Unlocked!',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper: show unlock overlay and auto-dismiss after 2.5s.
Future<void> showAchievementCelebration(
    BuildContext context, String achievementId) async {
  const achievements = {
    'first_rep': ('🏋️', 'First Rep'),
    'week_warrior': ('🔥', 'Week Warrior'),
    'century_club': ('💯', 'Century Club'),
    'ten_k_club': ('🏆', '10K Club'),
    'pr_machine': ('⭐', 'PR Machine'),
    'consistent': ('📅', 'Consistent'),
    'leg_day_hero': ('🦵', 'Leg Day Hero'),
    'note_taker': ('📓', 'Note Taker'),
  };
  final info = achievements[achievementId];
  if (info == null) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AchievementCelebrationDialog(
        emoji: info.$1, name: info.$2),
  );
  await Future.delayed(const Duration(milliseconds: 2500));
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
}
