import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loading = false;

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() => _loading = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) {
        setState(() => _loading = false);
        return;
      }

      // Open circular crop UI
      final cropped = await _cropPhoto(picked.path);
      if (cropped == null) {
        setState(() => _loading = false);
        return;
      }

      await _saveAndProceed(cropped);
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

  Future<void> _saveAndProceed(String sourcePath) async {
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
    _goHome();
  }

  Future<void> _skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
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
                      onPressed: _skip,
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
