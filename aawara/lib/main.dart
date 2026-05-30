import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'services/step_tracking_service.dart';
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  await StepTrackingService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aawara',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD700),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        canvasColor: const Color(0xFF1A1A2E),
        cardColor: const Color(0xFF1A1A2E),
        useMaterial3: true,
      ),
      home: const _LifecycleWrapper(child: SplashScreen()),
    );
  }
}

class _LifecycleWrapper extends StatefulWidget {
  final Widget child;
  const _LifecycleWrapper({required this.child});

  @override
  State<_LifecycleWrapper> createState() => _LifecycleWrapperState();
}

class _LifecycleWrapperState extends State<_LifecycleWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ensure service is running (may have failed on cold-start if the
      // Activity wasn't visible yet) then push fresh step count to UI.
      StepTrackingService.ensureAndroidServiceRunning();
      StepTrackingService.refreshStream();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
