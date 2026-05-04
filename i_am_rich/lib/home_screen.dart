import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late ConfettiController _confettiController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  String? _photoPath;
  // Timestamp key forces CircleAvatar to reload from disk after every update
  int _photoTimestamp = 0;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 4));
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
    _loadPhoto();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _audioPlayer.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_photo_path');
    final ts = prefs.getInt('profile_photo_ts') ?? 0;
    if (path != null && File(path).existsSync()) {
      setState(() {
        _photoPath = path;
        _photoTimestamp = ts;
      });
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    final cropped = await _cropPhoto(picked.path);
    if (cropped == null) return;

    await _savePhoto(cropped);
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

    // Evict old image from Flutter's cache before overwriting the file
    if (_photoPath != null) {
      await FileImage(File(_photoPath!)).evict();
    }
    imageCache.clear();
    imageCache.clearLiveImages();

    // Delete the old file first so the copy is guaranteed fresh
    final existing = File(dest);
    if (existing.existsSync()) await existing.delete();
    await File(sourcePath).copy(dest);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_path', dest);
    await prefs.setInt('profile_photo_ts', ts);

    if (!mounted) return;
    setState(() {
      _photoPath = dest;
      _photoTimestamp = ts;
    });
  }

  Future<void> _removePhoto() async {
    // Evict from cache first
    if (_photoPath != null) {
      await FileImage(File(_photoPath!)).evict();
    }
    imageCache.clear();
    imageCache.clearLiveImages();

    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_photo_path');
    if (path != null && File(path).existsSync()) {
      await File(path).delete();
    }
    await prefs.remove('profile_photo_path');
    await prefs.remove('profile_photo_ts');

    if (!mounted) return;
    setState(() {
      _photoPath = null;
      _photoTimestamp = 0;
    });
  }

  void _showPhotoOptions() {
    final hasPhoto = _photoPath != null;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFFFFD700)),
              title: const Text('Take a Photo',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFFFFD700)),
              title: const Text('Choose from Gallery',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (hasPhoto) ...[
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _removePhoto();
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Uint8List _generatePartySound() {
    const sampleRate = 44100;
    const numChannels = 1;
    const bitsPerSample = 16;
    final List<double> freqs = [523.25, 659.25, 783.99, 1046.50, 783.99, 1046.50];
    const noteDur = 0.10;
    final samplesPerNote = (sampleRate * noteDur).round();
    final numSamples = samplesPerNote * freqs.length;
    final buffer = ByteData(44 + numSamples * 2);
    int o = 0;

    void writeStr(String s) {
      for (final c in s.codeUnits) { buffer.setUint8(o++, c); }
    }
    void u32(int v) { buffer.setUint32(o, v, Endian.little); o += 4; }
    void u16(int v) { buffer.setUint16(o, v, Endian.little); o += 2; }

    writeStr('RIFF'); u32(36 + numSamples * 2); writeStr('WAVE');
    writeStr('fmt '); u32(16); u16(1); u16(numChannels);
    u32(sampleRate); u32(sampleRate * numChannels * bitsPerSample ~/ 8);
    u16(numChannels * bitsPerSample ~/ 8); u16(bitsPerSample);
    writeStr('data'); u32(numSamples * 2);

    for (int n = 0; n < freqs.length; n++) {
      for (int i = 0; i < samplesPerNote; i++) {
        final t = i / sampleRate;
        final envelope = (1.0 - i / samplesPerNote) * 0.85;
        final sample = (sin(2 * pi * freqs[n] * t) * 32767 * envelope)
            .round()
            .clamp(-32768, 32767);
        buffer.setInt16(o, sample, Endian.little);
        o += 2;
      }
    }
    return buffer.buffer.asUint8List();
  }

  Future<void> _celebrate() async {
    _confettiController.play();
    _scaleController.forward().then((_) => _scaleController.reverse());
    await _audioPlayer.play(BytesSource(_generatePartySound()));
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photoPath != null && File(_photoPath!).existsSync();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Stack(
        children: [
          // Radial glow background
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD700).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main content — Positioned.fill forces full screen width so
          // crossAxisAlignment.center works relative to the whole screen
          Positioned.fill(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                const Spacer(),

                // Photo avatar or diamond
                if (hasPhoto)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // ValueKey with timestamp forces a fresh widget + image load
                      CircleAvatar(
                        key: ValueKey(_photoTimestamp),
                        radius: 70,
                        backgroundImage: FileImage(File(_photoPath!)),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _showPhotoOptions,
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF0D0D1A),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: 15,
                              color: Color(0xFF1A1000),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  const Text('💎', style: TextStyle(fontSize: 96)),

                const SizedBox(height: 28),

                // I AM RICH gold gradient text
                IntrinsicWidth(
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFE566),
                        Color(0xFFFFD700),
                        Color(0xFFB8860B),
                        Color(0xFFFFD700),
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'I AM RICH',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'and you know it',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 16,
                    letterSpacing: 3,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 56),

                // Celebrate button
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: GestureDetector(
                    onTap: _celebrate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFE566), Color(0xFFFFAA00)],
                        ),
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Text(
                        '🎉  CELEBRATE  🎉',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1000),
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Small camera icon at bottom — only when no photo set
                if (!hasPhoto)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: GestureDetector(
                      onTap: _showPhotoOptions,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF444455), width: 1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Color(0xFF888899),
                          size: 22,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 48),
              ],
            ),
          ),
          ), // Positioned.fill

          // Confetti burst
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Color(0xFFFFD700), Color(0xFFFF4444), Color(0xFF44AAFF),
                Color(0xFF44FF88), Color(0xFFFF44FF), Color(0xFFFF8800), Color(0xFF88FFFF),
              ],
              numberOfParticles: 40,
              gravity: 0.12,
              emissionFrequency: 0.04,
              minBlastForce: 10,
              maxBlastForce: 40,
            ),
          ),
        ],
      ),
    );
  }
}
