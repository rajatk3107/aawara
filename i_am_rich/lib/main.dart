import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I Am Rich',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFD700)),
        useMaterial3: true,
      ),
      home: const RichPage(),
    );
  }
}

class RichPage extends StatefulWidget {
  const RichPage({super.key});

  @override
  State<RichPage> createState() => _RichPageState();
}

class _RichPageState extends State<RichPage> with SingleTickerProviderStateMixin {
  late ConfettiController _confettiController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

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
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _audioPlayer.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  // Generates a party horn sound as raw WAV bytes — no asset file needed
  Uint8List _generatePartySound() {
    const sampleRate = 44100;
    const numChannels = 1;
    const bitsPerSample = 16;

    // Ascending tones: C5, E5, G5, C6, G5, C6 — party horn feel
    final List<double> freqs = [523.25, 659.25, 783.99, 1046.50, 783.99, 1046.50];
    const noteDur = 0.10; // seconds per note
    final samplesPerNote = (sampleRate * noteDur).round();
    final numSamples = samplesPerNote * freqs.length;

    final buffer = ByteData(44 + numSamples * 2);
    int o = 0;

    void writeStr(String s) {
      for (final c in s.codeUnits) { buffer.setUint8(o++, c); }
    }
    void u32(int v) { buffer.setUint32(o, v, Endian.little); o += 4; }
    void u16(int v) { buffer.setUint16(o, v, Endian.little); o += 2; }

    // RIFF/WAVE header
    writeStr('RIFF');
    u32(36 + numSamples * 2);
    writeStr('WAVE');
    writeStr('fmt ');
    u32(16);         // subchunk size
    u16(1);          // PCM
    u16(numChannels);
    u32(sampleRate);
    u32(sampleRate * numChannels * bitsPerSample ~/ 8); // byte rate
    u16(numChannels * bitsPerSample ~/ 8);              // block align
    u16(bitsPerSample);
    writeStr('data');
    u32(numSamples * 2);

    // Audio samples — each note fades out for a punchy feel
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

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Diamond gem
                const Text('💎', style: TextStyle(fontSize: 96)),
                const SizedBox(height: 28),

                // "I AM RICH" with gold gradient
                ShaderMask(
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
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'and you know it',
                  style: TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 16,
                    letterSpacing: 3,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 56),

                // Celebrate button with scale animation
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
              ],
            ),
          ),

          // Confetti burst from top center
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Color(0xFFFFD700),
                Color(0xFFFF4444),
                Color(0xFF44AAFF),
                Color(0xFF44FF88),
                Color(0xFFFF44FF),
                Color(0xFFFF8800),
                Color(0xFF88FFFF),
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
