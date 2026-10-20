import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'case_screen.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({required this.session, required this.api, super.key});

  final CareFlowSession session;
  final CareFlowApi api;

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  final _clinicians = TextEditingController();
  final _intake = TextEditingController();
  final _reviewMinutes = TextEditingController();
  final _sampleSize = TextEditingController();
  final _note = TextEditingController();
  QueueIntelligence? _intelligence;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clinicians.dispose();
    _intake.dispose();
    _reviewMinutes.dispose();
    _sampleSize.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.get('/api/operations/staffing'),
        widget.api.get('/api/queue/intelligence'),
      ]);
      final staffing = Staffing.fromJson(results[0]);
      final intelligence = QueueIntelligence.fromJson(results[1]);
      _fillStaffing(staffing);
      if (!mounted) return;
      setState(() => _intelligence = intelligence);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillStaffing(Staffing staffing) {
    _clinicians.text = staffing.cliniciansAvailable.toString();
    _intake.text = staffing.intakeAvailable.toString();
    _reviewMinutes.text =
        staffing.averageReviewMinutes?.toStringAsFixed(1) ?? '';
    _sampleSize.text = staffing.sampleSize.toString();
  }

  Future<void> _save() async {
    final clinicians = int.tryParse(_clinicians.text.trim());
    final intake = int.tryParse(_intake.text.trim());
    if (clinicians == null || intake == null || clinicians < 0 || intake < 0) {
      _showMessage('Enter valid non-negative staffing counts.');
      return;
    }
    final minutesText = _reviewMinutes.text.trim();
    final minutes = minutesText.isEmpty ? null : double.tryParse(minutesText);
    if (minutesText.isNotEmpty && (minutes == null || minutes <= 0)) {
      _showMessage('Average review minutes must be a positive number.');
      return;
    }
    final sample = int.tryParse(_sampleSize.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      await widget.api.put(
        '/api/operations/staffing',
        body: {
          'clinicians_available': clinicians,
          'intake_available': intake,
          'average_review_minutes': minutes,
          'sample_size': sample,
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        },
      );
      _note.clear();
      await _load();
      if (!mounted) return;
      _showMessage('Staffing assumptions saved.');
    } on ApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [ErrorPanel(_error!, onRetry: _load)],
      );
    }
    final intelligence = _intelligence;
    final bottlenecks = intelligence?.bottlenecks ?? Bottlenecks();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Queue operations',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: careFlowNavy,
                        letterSpacing: -.3,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Staffing inputs and explainable bottlenecks.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF647A86)),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SectionCard(
            eyebrow: 'Capacity snapshot',
            title: 'Bottlenecks',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 560 ? 4 : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 9) / columns;
                final metrics = [
                  ('Waiting', bottlenecks.totalWaiting, Icons.hourglass_empty),
                  ('Overdue', bottlenecks.overdue, Icons.timer_off_outlined),
                  (
                    'Unassigned',
                    bottlenecks.unassigned,
                    Icons.person_off_outlined,
                  ),
                  (
                    'Emergency',
                    bottlenecks.emergency,
                    Icons.warning_amber_rounded,
                  ),
                  (
                    'Escalations',
                    bottlenecks.openEscalations,
                    Icons.campaign_outlined,
                  ),
                  (
                    'Pending messages',
                    bottlenecks.pendingCommunications,
                    Icons.mail_outline,
                  ),
                  (
                    'Pending follow-ups',
                    bottlenecks.pendingFollowups,
                    Icons.question_answer_outlined,
                  ),
                  ('Unassessed', bottlenecks.unassessed, Icons.help_outline),
                ];
                return Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: metrics.map((metric) {
                    final alert =
                        (metric.$1 == 'Overdue' ||
                            metric.$1 == 'Unassigned' ||
                            metric.$1 == 'Emergency' ||
                            metric.$1 == 'Escalations') &&
                        metric.$2 > 0;
                    return SizedBox(
                      width: width,
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: alert
                              ? const Color(0xFFFDEcea)
                              : const Color(0xFFF7FAFB),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: alert
                                ? const Color(0xFFF2BBB7)
                                : const Color(0xFFE1E9ED),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              metric.$3,
                              size: 18,
                              color: alert
                                  ? const Color(0xFFB3261E)
                                  : careFlowTeal,
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '${metric.$2}',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: alert
                                    ? const Color(0xFFB3261E)
                                    : careFlowNavy,
                              ),
                            ),
                            Text(
                              metric.$1,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF647A86),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            eyebrow: 'Explicit inputs only',
            title: 'Staffing assumptions',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _clinicians,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Clinicians available',
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: _intake,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Intake available',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reviewMinutes,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Avg review minutes',
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: _sampleSize,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Observed sample',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Assumption note (optional)',
                  ),
                ),
                const SizedBox(height: 2),
                FilledButton.icon(
                  onPressed: _saving || !widget.session.isStaff ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                    widget.session.isStaff ? 'Save staffing' : 'Clinician access required',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Wait estimates are shown only when staffing is available, '
                  'the average review time exists, and the observed sample meets '
                  'the configured minimum. Otherwise the estimate stays '
                  'unavailable.',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF647A86)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            eyebrow: 'Transparent ordering',
            title: 'Recommended work',
            child: (intelligence == null || intelligence.items.isEmpty)
                ? const EmptyState('No active cases to prioritize.')
                : Column(
                    children: intelligence.items.map((item) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAFB),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: const Color(0xFFE1E9ED)),
                        ),
                        child: ListTile(
                          onTap: () => _openCase(item.caseId),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: item.priorityRank <= 2
                                ? const Color(0xFFFDEcea)
                                : const Color(0xFFE5F4F1),
                            child: Text(
                              'P${item.priorityRank}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: item.priorityRank <= 2
                                    ? const Color(0xFFB3261E)
                                    : careFlowTeal,
                              ),
                            ),
                          ),
                          title: Text(
                            '${item.caseId} · ${item.status.replaceAll('_', ' ')}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            item.recommendedAction,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
