import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../services/supplement_events.dart';
import '../../services/supplement_payload.dart';

/// Listens for snooze requests (set when the user taps "Snooze" on a supplement
/// reminder) and presents the duration picker over whatever screen is active.
/// Mount once near the app root, above the Navigator.
class SnoozeRequestListener extends StatefulWidget {
  final Widget child;
  const SnoozeRequestListener({super.key, required this.child});

  @override
  State<SnoozeRequestListener> createState() => _SnoozeRequestListenerState();
}

class _SnoozeRequestListenerState extends State<SnoozeRequestListener> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    pendingSnoozeRequest.addListener(_onRequest);
    // Handle a request that arrived during a cold start (set before mount).
    if (pendingSnoozeRequest.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
    }
  }

  @override
  void dispose() {
    pendingSnoozeRequest.removeListener(_onRequest);
    super.dispose();
  }

  Future<void> _onRequest() async {
    final payload = pendingSnoozeRequest.value;
    if (payload == null || _showing || !mounted) return;
    _showing = true;
    clearSnoozeRequest();
    final minutes = await showSnoozePicker(context, payload);
    _showing = false;
    if (minutes == null) return;
    await NotificationService.instance.scheduleSnooze(
      supplementId: payload.id,
      name: payload.name,
      dose: payload.dose,
      minutes: minutes,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1A2E),
        content: Text(
          'Snoozed ${payload.name} for ${_label(minutes)}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  static String _label(int minutes) =>
      minutes >= 60 ? '${minutes ~/ 60} hour' : '$minutes min';

  @override
  Widget build(BuildContext context) => widget.child;
}

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
