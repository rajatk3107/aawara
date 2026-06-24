import 'package:flutter/foundation.dart';

import 'supplement_payload.dart';

/// Bumped whenever a supplement log is written from a notification action so an
/// open Supplements screen can reload its "taken today" state live.
final ValueNotifier<int> supplementsChanged = ValueNotifier<int>(0);

void notifySupplementsChanged() => supplementsChanged.value++;

/// Set when the user taps "Snooze" on a reminder. A listener at the app root
/// observes this and presents the snooze picker for the supplement, then clears
/// it. Survives a cold start (populated from the notification launch details).
final ValueNotifier<SupplementPayload?> pendingSnoozeRequest =
    ValueNotifier<SupplementPayload?>(null);

void requestSnooze(SupplementPayload payload) =>
    pendingSnoozeRequest.value = payload;

void clearSnoozeRequest() => pendingSnoozeRequest.value = null;
