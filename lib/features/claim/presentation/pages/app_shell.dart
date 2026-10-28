import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'appeal_page.dart';
import 'claim_page.dart';
import 'documents_page.dart';
import 'home_page.dart';
import 'tracker_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _navigateTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onNavigate: _navigateTo),
      ClaimPage(onNavigate: _navigateTo),
      DocumentsPage(),
      TrackerPage(),
      AppealPage(),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _navigateTo,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.mint,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.health_and_safety_outlined), selectedIcon: Icon(Icons.health_and_safety), label: 'Claim'),
          NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_open), label: 'Documents'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: 'Track'),
          NavigationDestination(icon: Icon(Icons.edit_document), selectedIcon: Icon(Icons.edit_document), label: 'Draft'),
        ],
      ),
    );
  }
}
