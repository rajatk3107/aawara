import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_refresh.dart';
import 'services/notification_service.dart';
import 'services/supplement_events.dart';
import 'workout/screens/workout_home_screen.dart';
import 'workout/screens/progress_screen.dart';
import 'workout/screens/workout_history_screen.dart';
import 'workout/widgets/snooze_picker_sheet.dart';
import 'settings_screen.dart';
import 'nutrition/screens/nutrition_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver, RouteAware {
  int _tab = 0;

  // Tabs live in an IndexedStack (kept alive to preserve scroll/state), so they
  // only load in initState. These keys let us re-fetch the visible tab's data
  // whenever it becomes current again.
  final List<GlobalKey> _keys = List.generate(5, (_) => GlobalKey());

  late final List<Widget> _screens = [
    WorkoutHomeScreen(key: _keys[0]),
    ProgressScreen(key: _keys[1]),
    NutritionScreen(key: _keys[2]),
    WorkoutHistoryScreen(key: _keys[3]),
    SettingsScreen(key: _keys[4]),
  ];

  void _refreshTab(int i) {
    final state = _keys[i].currentState;
    if (state is RefreshableState) (state as RefreshableState).refreshData();
  }

  bool _showingSnooze = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Snooze taps route here (the persistent host) so the picker isn't torn
    // down by splash navigation. Handles both runtime requests and one set
    // during a cold start before this screen mounted.
    pendingSnoozeRequest.addListener(_handleSnoozeRequest);
    if (pendingSnoozeRequest.value != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _handleSnoozeRequest());
    }
  }

  Future<void> _handleSnoozeRequest() async {
    final payload = pendingSnoozeRequest.value;
    if (payload == null || _showingSnooze || !mounted) return;
    _showingSnooze = true;
    await handleSnoozeRequest(context, payload);
    _showingSnooze = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    pendingSnoozeRequest.removeListener(_handleSnoozeRequest);
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Returned to this screen after a pushed route/dialog/sheet was popped.
  @override
  void didPopNext() => _refreshTab(_tab);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Apply "taken" actions captured while backgrounded, then refresh.
      NotificationService.instance.drainPendingTaken();
      _refreshTab(_tab);
    }
  }

  void _onTabSelected(int i) {
    setState(() => _tab = i);
    _refreshTab(i);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0xFF0D0D1A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        resizeToAvoidBottomInset: false,
        body: IndexedStack(index: _tab, children: _screens),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFF1E1E35), width: 1),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _onTabSelected,
            backgroundColor: const Color(0xFF0D0D1A),
            indicatorColor: const Color(0xFFFFD700).withValues(alpha: 0.15),
            labelBehavior:
                NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded, color: Color(0xFFFFD700)),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon:
                    Icon(Icons.bar_chart_rounded, color: Color(0xFFFFD700)),
                label: 'Progress',
              ),
              NavigationDestination(
                icon: Icon(Icons.restaurant_outlined),
                selectedIcon:
                    Icon(Icons.restaurant_rounded, color: Color(0xFFFFD700)),
                label: 'Nutrition',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon:
                    Icon(Icons.history_rounded, color: Color(0xFFFFD700)),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon:
                    Icon(Icons.settings_rounded, color: Color(0xFFFFD700)),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
