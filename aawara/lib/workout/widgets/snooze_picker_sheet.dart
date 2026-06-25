import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../services/supplement_events.dart';
import '../../services/supplement_payload.dart';

/// Drives the snooze flow from a persistent host (e.g. MainScreen): shows the
/// duration picker for [payload], reschedules the reminder, and confirms.
///
/// [context] must sit below a Navigator and ScaffoldMessenger. Call from a
/// screen that is not torn down by navigation so the picker isn't dismissed
/// mid-show.
Future<void> handleSnoozeRequest(
    BuildContext context, SupplementPayload payload) async {
  clearSnoozeRequest();
  final minutes = await showSnoozePicker(context, payload);
  if (minutes == null) return;
  await NotificationService.instance.scheduleSnooze(
    supplementId: payload.id,
    name: payload.name,
    dose: payload.dose,
    minutes: minutes,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFF1A1A2E),
      content: Text(
        'Snoozed ${payload.name} for ${_snoozeLabel(minutes)}',
        style: const TextStyle(color: Colors.white),
      ),
    ),
  );
}

String _snoozeLabel(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60} hour' : '$minutes min';

/// Shows the snooze duration picker. Returns the chosen minutes, or null.
Future<int?> showSnoozePicker(
    BuildContext context, SupplementPayload payload) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _SnoozePickerSheet(payload: payload),
  );
}

class _SnoozePickerSheet extends StatelessWidget {
  final SupplementPayload payload;
  const _SnoozePickerSheet({required this.payload});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF333355),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Snooze ${payload.name}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Remind me again in…',
              style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
          const SizedBox(height: 18),
          Row(
            children: [
              _chip(context, '15 min', 15),
              const SizedBox(width: 10),
              _chip(context, '30 min', 30),
              const SizedBox(width: 10),
              _chip(context, '1 hour', 60),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, int minutes) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.pop(context, minutes),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A45)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
