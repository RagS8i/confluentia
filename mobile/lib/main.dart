import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/home_shell.dart';
import 'session.dart';
import 'theme.dart';

void main() {
  runApp(const CareFlowApp());
}

class CareFlowApp extends StatefulWidget {
  const CareFlowApp({super.key});

  @override
  State<CareFlowApp> createState() => _CareFlowAppState();
}

class _CareFlowAppState extends State<CareFlowApp> {
  late final CareFlowSession _session;
  late final CareFlowApi _api;

  @override
  void initState() {
    super.initState();
    _session = CareFlowSession();
    _api = CareFlowApi(_session);
    _session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CareFlow AI',
      debugShowCheckedModeBanner: false,
      theme: buildCareFlowTheme(),
      home: HomeShell(
        key: ValueKey(
          '${_session.baseUrl}|${_session.userId}|${_session.role}',
        ),
        session: _session,
        api: _api,
      ),
    );
  }
}
