import 'package:flutter/material.dart';
import '../../workout/database/workout_database.dart';
import '../../utils/safe_navigation.dart';

/// Shows a bottom sheet listing active meals with an option to create a new one.
/// Returns the selected [mealKey], or null if dismissed.
Future<String?> showMealPickerSheet(
  BuildContext context, {
  required Map<String, String> mealNames,
  required Map<String, String> defaultMealNames,
  required List<String> mealKeys,
  required Map<String, String> mealIcons,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MealPickerSheet(
      mealNames: mealNames,
      defaultMealNames: defaultMealNames,
      mealKeys: mealKeys,
      mealIcons: mealIcons,
    ),
  );
}

class MealPickerSheet extends StatefulWidget {
  final Map<String, String> mealNames;
  final Map<String, String> defaultMealNames;
  final List<String> mealKeys;
  final Map<String, String> mealIcons;

  const MealPickerSheet({
    super.key,
    required this.mealNames,
    required this.defaultMealNames,
    required this.mealKeys,
    required this.mealIcons,
  });

  @override
  State<MealPickerSheet> createState() => _MealPickerSheetState();
}

class _MealPickerSheetState extends State<MealPickerSheet> {
  final _db = WorkoutDatabase.instance;
  bool _creating = false;

  String _displayName(String key) =>
      widget.mealNames[key] ?? widget.defaultMealNames[key] ?? key;

  String _icon(String key) => widget.mealIcons[key] ?? '🍽️';

  Future<void> _createAndSelect() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New Meal',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Evening Snack',
            hintStyle: const TextStyle(color: Color(0xFF444466)),
            filled: true,
            fillColor: const Color(0xFF0D0D1A),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFFD700))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => popAfterFocusSettles(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              popAfterFocusSettles(ctx, v.isNotEmpty ? v : null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || !mounted) return;

    setState(() => _creating = true);
    final newKey = await _db.createMealSlot(name);
    if (mounted) Navigator.pop(context, newKey);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPad),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFF333355),
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Row(
              children: [
                const Text('Add to meal',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: Color(0xFF555577), size: 20),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E1E35), height: 1),
          // Existing meals
          ...widget.mealKeys.map((key) => ListTile(
                leading: Text(_icon(key),
                    style: const TextStyle(fontSize: 22)),
                title: Text(_displayName(key),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF444466), size: 20),
                onTap: () => Navigator.pop(context, key),
              )),
          const Divider(color: Color(0xFF1E1E35), height: 1),
          // Create new meal
          ListTile(
            leading: _creating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFFFD700)))
                : Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Color(0xFFFFD700), size: 20),
                  ),
            title: const Text('Create new meal',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            subtitle: const Text('Add a 6th, 7th meal, etc.',
                style: TextStyle(color: Color(0xFF555577), fontSize: 12)),
            onTap: _creating ? null : _createAndSelect,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
