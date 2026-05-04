import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'onboarding_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_photo_path');

    if (mounted) {
      setState(() {
        _photoPath = (path != null && File(path).existsSync()) ? path : null;
      });
    }

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final isFirstLaunch = prefs.getBool('onboarding_complete') != true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => isFirstLaunch ? const OnboardingScreen() : const MainScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: _photoPath != null
            ? CircleAvatar(
                radius: 80,
                backgroundImage: FileImage(File(_photoPath!)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💎', style: TextStyle(fontSize: 96)),
                  const SizedBox(height: 20),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFFFE566), Color(0xFFFFD700), Color(0xFFB8860B)],
                    ).createShader(bounds),
                    child: const Text(
                      'RICHIE RICH',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
