import 'package:flutter/widgets.dart';

/// Global route observer so screens can react when a route pushed on top of
/// them is popped (i.e. the user navigates *back* to them).
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Implemented by tab screens that need their data re-fetched when they become
/// visible again (tab switch, app resume, or returning from a pushed screen).
abstract interface class RefreshableState {
  void refreshData();
}
