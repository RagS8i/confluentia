import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import 'operations_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({required this.session, required this.api, super.key});

  final CareFlowSession session;
  final CareFlowApi api;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final showOperations = widget.session.canViewIntelligence;
    final pages = <Widget>[
      QueueScreen(session: widget.session, api: widget.api),
      if (showOperations) OperationsScreen(session: widget.session, api: widget.api),
      SettingsScreen(
        session: widget.session,
        onSaved: () => setState(() => _index = 0),
      ),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.view_list_outlined),
        selectedIcon: Icon(Icons.view_list),
        label: 'Queue',
      ),
      if (showOperations)
        const NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: 'Operations',
        ),
      const NavigationDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: 'Settings',
      ),
    ];

    if (_index >= pages.length) _index = 0;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/logo.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: careFlowNavy,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    color: careFlowMint,
                    size: 21,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CareFlow AI',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.3,
                  ),
                ),
                Text(
                  'Queue coordination workspace',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF647A86),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: const Color(0xFFD8E3E8)),
            ),
            child: Text(
              widget.session.role.replaceAll('_', ' '),
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: careFlowTeal,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: destinations,
      ),
    );
  }
}
