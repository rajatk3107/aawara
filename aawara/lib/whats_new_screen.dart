import 'package:flutter/material.dart';

import 'changelog.dart';

const _bg = Color(0xFF0D0D1A);
const _card = Color(0xFF1A1A2E);
const _border = Color(0xFF1E1E35);
const _muted = Color(0xFF888899);
const _gold = Color(0xFFFFD700);

class WhatsNewScreen extends StatelessWidget {
  /// When true, shown automatically after an update (latest release highlighted).
  final bool isUpdate;
  const WhatsNewScreen({super.key, this.isUpdate = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("What's New",
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          for (int i = 0; i < kChangelog.length; i++)
            _entryCard(kChangelog[i], highlight: isUpdate && i == 0),
          if (isUpdate)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Got it',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entryCard(ChangelogEntry e, {required bool highlight}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight ? _gold : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Version ${e.version}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (highlight)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('NEW',
                      style: TextStyle(
                          color: _gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                ),
              const Spacer(),
              Text(e.date,
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          for (final c in e.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 10),
                    child: SizedBox(
                      width: 5,
                      height: 5,
                      child: DecoratedBox(
                        decoration:
                            BoxDecoration(color: _gold, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(c,
                        style: const TextStyle(
                            color: Color(0xFFCCCCDD),
                            fontSize: 13,
                            height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
