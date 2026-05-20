import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const Text(
          'Privacy Policy',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: const [
          _Section(
            title: 'Data Collection',
            body:
                'Aawara collects no personal data. No accounts, no servers, no analytics.',
          ),
          _Section(
            title: 'Storage',
            body:
                'All data (workouts, body weight, notes) is stored locally on your device using SQLite and never leaves your phone.',
          ),
          _Section(
            title: 'Permissions',
            body:
                'The app requests access to your photo library only for setting your profile picture. No other permissions are required.',
          ),
          _Section(
            title: 'Contact',
            body: 'rajatky3107@gmail.com',
          ),
          _Section(
            title: 'Last Updated',
            body: 'May 19, 2026',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFFCCCCDD),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1E1E35), thickness: 1),
        ],
      ),
    );
  }
}
