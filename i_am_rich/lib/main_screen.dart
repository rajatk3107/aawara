import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'notes/notes_list_screen.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageView(
      physics: const ClampingScrollPhysics(),
      children: const [
        HomeScreen(),
        NotesListScreen(),
      ],
    );
  }
}
