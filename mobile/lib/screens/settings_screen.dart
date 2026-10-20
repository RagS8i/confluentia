import 'package:flutter/material.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.session,
    required this.onSaved,
    super.key,
  });

  final CareFlowSession session;
  final VoidCallback onSaved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _userId;
  late final TextEditingController _patientId;
  late String _role;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.session.baseUrl);
    _userId = TextEditingController(text: widget.session.userId);
    _patientId = TextEditingController(text: widget.session.patientId);
    _role = widget.session.role;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _userId.dispose();
    _patientId.dispose();
    super.dispose();
  }

  void _save() {
    final rawUrl = _baseUrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid http:// or https:// base URL.'),
        ),
      );
      return;
    }
    widget.session.update(
      baseUrl: rawUrl,
      userId: _userId.text,
      role: _role,
      patientId: _patientId.text,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection settings applied.')),
    );
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
      children: [
        const Text(
          'Connection & identity',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: careFlowNavy,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'The mobile app uses the same development identity headers as the '
          'website. Use real authentication before any production deployment.',
          style: TextStyle(fontSize: 12, color: Color(0xFF647A86)),
        ),
        const SizedBox(height: 14),
        SectionCard(
          eyebrow: 'Server',
          title: 'CareFlow endpoint',
          child: Column(
            children: [
              TextField(
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'http://10.0.2.2:8000',
                  prefixIcon: Icon(Icons.dns_outlined, size: 19),
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Android emulator uses 10.0.2.2 for the host machine. iOS '
                'simulator uses 127.0.0.1. Physical devices need the host LAN '
                'address. Plain HTTP is enabled for local development only.',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF647A86)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          eyebrow: 'Request context',
          title: 'Identity',
          child: Column(
            children: [
              TextField(
                controller: _userId,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'User ID',
                  prefixIcon: Icon(Icons.badge_outlined, size: 19),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.manage_accounts_outlined, size: 19),
                ),
                items: const ['clinician', 'admin', 'intake', 'patient']
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.replaceAll('_', ' ')),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              if (_role == 'patient') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _patientId,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Patient ID',
                    prefixIcon: Icon(Icons.person_outline, size: 19),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Apply settings'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          eyebrow: 'Safety boundary',
          title: 'What this app does not do',
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SafetyLine(
                'No diagnosis, prescription, or clinical clearance is produced.',
              ),
              _SafetyLine(
                'Demo triage rules are illustrative and not clinically approved.',
              ),
              _SafetyLine(
                'Wait estimates remain unavailable without staffing and sample data.',
              ),
              _SafetyLine(
                'Messages and follow-up questions require staff approval before delivery.',
              ),
              _SafetyLine(
                'Emergency cases require immediate human emergency care.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyLine extends StatelessWidget {
  const _SafetyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.shield_outlined, size: 15, color: careFlowTeal),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
