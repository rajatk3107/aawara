import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'workout/screens/workout_home_screen.dart';
import 'workout/screens/progress_screen.dart';
import 'workout/screens/workout_history_screen.dart';
import 'settings_screen.dart';
import 'nutrition/screens/nutrition_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  static const _screens = [
    WorkoutHomeScreen(),
    ProgressScreen(),
    NutritionScreen(),
    WorkoutHistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0xFF0D0D1A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        body: IndexedStack(index: _tab, children: _screens),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFF1E1E35), width: 1),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
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
