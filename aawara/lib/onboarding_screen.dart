import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'workout/database/workout_database.dart';
import 'main_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0 = photo, 1 = goal
  bool _loading = false;
  bool _seeding = false;

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => _loading = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) {
        setState(() => _loading = false);
        return;
      }
      final cropped = await _cropPhoto(picked.path);
      if (cropped == null) {
        setState(() => _loading = false);
        return;
      }
      await _savePhoto(cropped);
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<String?> _cropPhoto(String sourcePath) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Adjust Photo',
          toolbarColor: const Color(0xFF0D0D1A),
          toolbarWidgetColor: const Color(0xFFFFD700),
          backgroundColor: Colors.black,
          activeControlsWidgetColor: const Color(0xFFFFD700),
          cropStyle: CropStyle.circle,
          lockAspectRatio: true,
          hideBottomControls: false,
          showCropGrid: false,
        ),
        IOSUiSettings(
          title: 'Adjust Photo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    return croppedFile?.path;
  }

  Future<void> _savePhoto(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/profile_photo.jpg';
    final existing = File(dest);
    if (existing.existsSync()) await existing.delete();
    await File(sourcePath).copy(dest);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_path', dest);
    await prefs.setInt('profile_photo_ts', ts);
    await prefs.setBool('onboarding_complete', true);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _step = 1;
    });
  }

  Future<void> _skipPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;
    setState(() => _step = 1);
  }

  Future<void> _selectGoal(String goal) async {
    setState(() => _seeding = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_goal', goal);
      await WorkoutDatabase.instance.seedGoalPlan(goal);
    } catch (_) {}
    if (!mounted) return;
    _goHome();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _step == 0 ? _buildPhotoStep() : _buildGoalStep();
  }

  Widget _buildPhotoStep() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD700)),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '📸',
                      style: TextStyle(fontSize: 72),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Add a profile photo',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your photo will appear on the home screen\nand splash screen every time you open the app.',
                      style: TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 14,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    _OptionButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Take a Photo',
                      onTap: () => _pickPhoto(ImageSource.camera),
                    ),
                    const SizedBox(height: 16),
                    _OptionButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Choose from Gallery',
                      onTap: () => _pickPhoto(ImageSource.gallery),
                    ),
                    const SizedBox(height: 36),
                    TextButton(
                      onPressed: _skipPhoto,
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildGoalStep() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: _seeding
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD700)),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 48),
                    const Text(
                      "What's your goal?",
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "We'll set up a training plan to match.",
                      style: TextStyle(
                          color: Color(0xFF888899), fontSize: 14, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.88,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _GoalCard(
                            icon: Icons.fitness_center_rounded,
                            color: const Color(0xFFFF6B35),
                            title: 'Muscle Gain',
                            subtitle: '6-day PPL split',
                            onTap: () => _selectGoal('muscle_gain'),
                          ),
                          _GoalCard(
                            icon: Icons.bolt_rounded,
                            color: const Color(0xFF3498DB),
                            title: 'Strength',
                            subtitle: '4-day Upper/Lower',
                            onTap: () => _selectGoal('strength'),
                          ),
                          _GoalCard(
                            icon: Icons.local_fire_department_rounded,
                            color: const Color(0xFF2ECC71),
                            title: 'Weight Loss',
                            subtitle: '3-day Full Body',
                            onTap: () => _selectGoal('weight_loss'),
                          ),
                          _GoalCard(
                            icon: Icons.self_improvement_rounded,
                            color: const Color(0xFF9B59B6),
                            title: 'General Fitness',
                            subtitle: '3-day A/B split',
                            onTap: () => _selectGoal('general_fitness'),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _goHome,
                      child: const Text(
                        "Skip — I'll set up my plan later",
                        style: TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 14,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFFFFD700), size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _GoalCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF888899),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
