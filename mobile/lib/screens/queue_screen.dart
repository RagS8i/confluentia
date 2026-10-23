import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'case_screen.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({required this.session, required this.api, super.key});

  final CareFlowSession session;
  final CareFlowApi api;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  QueueIntelligence? _intelligence;
  List<CaseSummary> _cases = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.session.canViewIntelligence) {
        final data = await widget.api.get('/api/queue/intelligence');
        final parsed = QueueIntelligence.fromJson(data);
        if (!mounted) return;
        setState(() => _intelligence = parsed);
      } else {
        final data = await widget.api.get('/api/cases');
        final list = caseSummariesFromResponse(data);
        if (!mounted) return;
        setState(() {
          _cases = list;
          _intelligence = null;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCase() async {
    final patientController = TextEditingController(
      text: widget.session.isPatient ? widget.session.patientId : '',
    );
    final symptomsController = TextEditingController();
    bool grantConsent = true;
    bool autoProcess = true;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Register a case'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.session.isPatient
                        ? 'A new case will be linked to your patient identity.'
                        : 'Enter the patient identifier and initial clinical intake details.',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF647A86)),
                  ),
                  if (!widget.session.isPatient) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: patientController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Patient ID',
                        hintText: 'e.g. patient_102',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: symptomsController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Initial symptoms / case details (optional)',
                      hintText:
                          'Describe chief complaint, symptoms, onset, or medical history...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Record patient consent',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Required before AI intake, transcription, and triage',
                      style: TextStyle(fontSize: 11, color: Color(0xFF647A86)),
                    ),
                    value: grantConsent,
                    onChanged: (val) =>
                        setDialogState(() => grantConsent = val),
                  ),
                  if (grantConsent)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Run processing immediately',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Extract facts, advisory urgency, and clinical summary',
                        style: TextStyle(fontSize: 11, color: Color(0xFF647A86)),
                      ),
                      value: autoProcess,
                      onChanged: (val) =>
                          setDialogState(() => autoProcess = val),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create & open'),
            ),
          ],
        ),
      ),
    );
    if (created != true) return;
    try {
      final patientId = widget.session.isPatient
          ? widget.session.patientId
          : patientController.text.trim();
      final data = await widget.api.post(
        '/api/cases',
        body: {
          'patient_id': patientId.isEmpty ? 'patient_anonymous' : patientId,
        },
      );
      final caseMap = mapValue(data);
      final caseId = textValue(caseMap['case_id']);
      if (!mounted || caseId.isEmpty) return;

      if (grantConsent) {
        try {
          await widget.api.post(
            '/api/cases/$caseId/consent',
            body: {'scope': 'careflow_processing_and_review'},
          );
        } catch (_) {}
      }

      final symptoms = symptomsController.text.trim();
      if (symptoms.isNotEmpty && grantConsent) {
        try {
          await widget.api.post(
            '/api/cases/$caseId/sources/message',
            body: {'text': symptoms},
          );
          if (autoProcess) {
            await widget.api.post('/api/cases/$caseId/process?sync=true');
          }
        } catch (_) {}
      }

      await _openCase(caseId);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _openCase(String caseId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaseScreen(
          session: widget.session,
          api: widget.api,
          caseId: caseId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _QueueHero(
            isStaff: widget.session.canViewIntelligence,
            onRefresh: _load,
            onCreate: _createCase,
          ),
          if (widget.session.isPatient) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'You can see only your own cases. Emergency symptoms require '
                'immediate human emergency care; this app does not provide '
                'clinical clearance or a diagnosis.',
                style: TextStyle(fontSize: 12, color: Color(0xFF334D5C)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const LoadingList()
          else if (_error != null)
            ErrorPanel(_error!, onRetry: _load)
          else if (widget.session.canViewIntelligence)
            ..._buildStaffContent()
          else
            ..._buildPatientContent(),
        ],
      ),
    );
  }

  List<Widget> _buildStaffContent() {
    final intelligence = _intelligence;
    if (intelligence == null) {
      return const [EmptyState('No queue intelligence is available yet.')];
    }
    final bottlenecks = intelligence.bottlenecks;
    final items = intelligence.items;
    return [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Queue priorities',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: careFlowNavy,
              ),
            ),
          ),
          Text(
            '${items.length} active',
            style: const TextStyle(fontSize: 12, color: Color(0xFF647A86)),
          ),
        ],
      ),
      const SizedBox(height: 9),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MetricPill(
            label: 'Waiting',
            value: '${bottlenecks.totalWaiting}',
            icon: Icons.hourglass_empty,
          ),
          _MetricPill(
            label: 'Overdue',
            value: '${bottlenecks.overdue}',
            icon: Icons.timer_off_outlined,
            alert: bottlenecks.overdue > 0,
          ),
          _MetricPill(
            label: 'Unassigned',
            value: '${bottlenecks.unassigned}',
            icon: Icons.person_off_outlined,
            alert: bottlenecks.unassigned > 0,
          ),
          _MetricPill(
            label: 'Open escalations',
            value: '${bottlenecks.openEscalations}',
            icon: Icons.campaign_outlined,
            alert: bottlenecks.openEscalations > 0,
          ),
        ],
      ),
      const SizedBox(height: 13),
      if (items.isEmpty)
        const SectionCard(
          title: 'Nothing waiting',
          child: EmptyState(
            'There are no active cases in the queue.',
            icon: Icons.check_circle_outline,
          ),
        )
      else
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _QueueCaseCard(
              item: item,
              onTap: () => _openCase(item.caseId),
            ),
          ),
        ),
      if (intelligence.disclaimer.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          intelligence.disclaimer,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF647A86)),
        ),
      ],
    ];
  }

  List<Widget> _buildPatientContent() {
    if (_cases.isEmpty) {
      return const [
        SectionCard(
          title: 'Your cases',
          child: EmptyState(
            'You have no cases yet. Create one to begin intake.',
            icon: Icons.folder_open_outlined,
          ),
        ),
      ];
    }
    return _cases
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openCase(item.caseId),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.caseId,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${item.workflowStatus.replaceAll('_', ' ')} · '
                              'consent ${item.consent} · '
                              '${item.urgencyScore != null ? 'urgency ${item.urgencyScore}/100 · ' : ''}'
                              '${item.warningCount} warning(s)',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF647A86),
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(item.status),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
  }
}

class _QueueHero extends StatelessWidget {
  const _QueueHero({
    required this.isStaff,
    required this.onRefresh,
    required this.onCreate,
  });

  final bool isStaff;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [careFlowNavy, Color(0xFF0D4B56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isStaff ? 'Operational queue' : 'Your care queue',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isStaff
                          ? 'Explainable ordering within each triage category.'
                          : 'Track your intake, messages, and follow-up requests.',
                      style: const TextStyle(
                        color: Color(0xFFC8DCE1),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 19),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: .12),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New case'),
                style: FilledButton.styleFrom(
                  backgroundColor: careFlowMint,
                  foregroundColor: careFlowNavy,
                ),
              ),
              const SizedBox(width: 9),
              OutlinedButton(
                onPressed: onRefresh,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF47727D)),
                ),
                child: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.icon,
    this.alert = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert ? const Color(0xFFB3261E) : careFlowTeal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: alert ? const Color(0xFFFDEcea) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: alert ? const Color(0xFFF2BBB7) : const Color(0xFFD8E3E8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$value $label',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: alert ? color : careFlowNavy,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueCaseCard extends StatelessWidget {
  const _QueueCaseCard({required this.item, required this.onTap});

  final QueueRecommendation item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgent = item.priorityRank <= 2;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 37,
                    height: 37,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: urgent
                          ? const Color(0xFFFDEcea)
                          : const Color(0xFFE5F4F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'P${item.priorityRank}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        color: urgent ? const Color(0xFFB3261E) : careFlowTeal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.caseId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            StatusChip(item.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.patientId} · '
                          '${item.workflowStatus.replaceAll('_', ' ')}'
                          '${item.urgencyScore != null ? ' · urgency ${item.urgencyScore}/100' : ''}'
                          '${item.awaitingMinutes != null ? ' · ${item.awaitingMinutes} min awaiting' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF647A86),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.recommendedAction,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: careFlowNavy,
                ),
              ),
              if (item.explanations.isNotEmpty) ...[
                const SizedBox(height: 7),
                ...item.explanations
                    .take(3)
                    .map(
                      (explanation) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'â€¢ ',
                              style: TextStyle(color: careFlowTeal),
                            ),
                            Expanded(
                              child: Text(
                                explanation,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF647A86),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              if (item.waitEstimate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      item.waitEstimate!.available
                          ? Icons.schedule
                          : Icons.schedule_outlined,
                      size: 14,
                      color: const Color(0xFF647A86),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Estimate: ${item.waitEstimate!.label}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF647A86),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 9),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    'Open case',
                    style: TextStyle(
                      color: careFlowTeal,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: careFlowTeal,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
