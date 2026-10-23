import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

const _messageIntents = {
  'status_update': 'Routine status update',
  'wait_update': 'Operational wait update',
  'missing_information': 'Request missing information',
  'document_request': 'Request a document',
  'urgent_review': 'Urgent review notice',
};

const _languages = {'en': 'English', 'hi': 'Hindi', 'hinglish': 'Hinglish'};

class CaseScreen extends StatefulWidget {
  const CaseScreen({
    required this.session,
    required this.api,
    required this.caseId,
    super.key,
  });

  final CareFlowSession session;
  final CareFlowApi api;
  final String caseId;

  @override
  State<CaseScreen> createState() => _CaseScreenState();
}

class _CaseScreenState extends State<CaseScreen> {
  CaseDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _staff => widget.session.isStaff;

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
      final data = await widget.api.get('/api/cases/${widget.caseId}');
      final parsed = CaseDetail.fromJson(data);
      if (!mounted) return;
      setState(() => _detail = parsed);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askText({
    required String title,
    required String label,
    String initialValue = '',
    String? helper,
    int maxLines = 1,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (helper != null) ...[
                Text(
                  helper,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF647A86),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                minLines: maxLines,
                maxLines: maxLines == 1 ? 2 : 6,
                decoration: InputDecoration(labelText: label),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _grantConsent({
    String scope = 'careflow_processing_and_review',
  }) async {
    await _run(
      () => widget.api.post(
        '/api/cases/${widget.caseId}/consent',
        body: {'scope': scope},
      ),
      'Patient consent recorded for AI intake and processing.',
    );
  }

  Future<void> _withdrawConsent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw patient consent'),
        content: const Text(
          'Withdrawing consent immediately suspends AI processing and '
          'intake. Are you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Withdraw consent'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.api.post(
        '/api/cases/${widget.caseId}/consent/withdraw',
        body: {
          'reason': 'Patient or clinician requested withdrawal via mobile',
          'delete_data': false,
        },
      ),
      'Consent withdrawn.',
    );
  }

  Future<void> _addSource() async {
    final textController = TextEditingController();
    bool autoProcess = true;
    final needsConsent =
        _detail != null && !_detail!.hasConsent && !_detail!.isConsentWithdrawn;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add patient intake / source'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Input patient symptoms, chief complaint, medical notes, or clinical history.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF647A86)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Symptoms / clinical intake text',
                      hintText:
                          'e.g. 52-year-old presenting with sharp substernal chest pressure radiating to left arm for 45 minutes, diaphoresis, shortness of breath...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (needsConsent)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFCC80)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.privacy_tip_outlined,
                            size: 18,
                            color: Color(0xFFE65100),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Patient consent will be recorded automatically with this intake.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFFE65100),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Run pipeline processing immediately',
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
                    onChanged: (val) => setDialogState(() => autoProcess = val),
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
              onPressed: () {
                if (textController.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Submit source'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final intakeText = textController.text.trim();
    if (intakeText.isEmpty) return;

    await _run(() async {
      if (needsConsent) {
        await widget.api.post(
          '/api/cases/${widget.caseId}/consent',
          body: {'scope': 'careflow_processing_and_review'},
        );
      }
      await widget.api.post(
        '/api/cases/${widget.caseId}/sources/message',
        body: {'text': intakeText},
      );
      if (autoProcess) {
        await widget.api.post('/api/cases/${widget.caseId}/process?sync=true');
      }
    }, 'Intake source saved${autoProcess ? ' and case processed.' : '.'}');
  }

  Future<void> _process() async {
    if (_detail != null &&
        !_detail!.hasConsent &&
        !_detail!.isConsentWithdrawn) {
      final grant = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Consent required'),
          content: const Text(
            'Pipeline processing requires recorded patient consent. '
            'Would you like to record patient consent and proceed with processing?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Grant consent & process'),
            ),
          ],
        ),
      );
      if (grant != true) return;
      await widget.api.post(
        '/api/cases/${widget.caseId}/consent',
        body: {'scope': 'careflow_processing_and_review'},
      );
    }
    await _run(
      () => widget.api.post('/api/cases/${widget.caseId}/process?sync=true'),
      'Case processing finished.',
    );
  }

  Future<void> _assign() async {
    final reviewer = await _askText(
      title: 'Assign reviewer',
      label: 'Reviewer ID',
      initialValue: _detail?.meta['assigned_reviewer']?.toString() ?? '',
      helper:
          'Assignment is audited. Only a named staff member can receive '
          'the case; no automatic reassignment occurs.',
    );
    if (reviewer == null) return;
    await _run(
      () => widget.api.post(
        '/api/cases/${widget.caseId}/assign',
        body: {'reviewer': reviewer, 'confirmed': true},
      ),
      'Reviewer assigned.',
    );
  }

  Future<void> _editUrgency() async {
    final urgency = _detail?.urgency;
    final scoreController = TextEditingController(
      text: urgency == null ? '' : '${urgency.score}',
    );
    final reasonController = TextEditingController();
    final rationaleController = TextEditingController(
      text: urgency?.rationale ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit advisory urgency'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The SLM score is advisory. Editing it does not change the '
                'workflow category and is fully audited.',
                style: TextStyle(fontSize: 12, color: Color(0xFF647A86)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Urgency score (0-100)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason for change (required)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rationaleController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Clinical rationale (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final score = int.tryParse(scoreController.text.trim());
    if (score == null || score < 0 || score > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Urgency must be a whole number from 0 to 100.'),
        ),
      );
      return;
    }
    final reason = reasonController.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A documented reason is required.')),
      );
      return;
    }
    final rationale = rationaleController.text.trim();
    await _run(
      () => widget.api.patch(
        '/api/cases/${widget.caseId}/urgency',
        body: {
          'score': score,
          'reason': reason,
          'rationale': rationale.isEmpty ? null : rationale,
          'confirmed': true,
        },
      ),
      'Urgency score updated.',
    );
  }

  Future<void> _override() async {
    final reason = await _askText(
      title: 'Override triage outcome',
      label: 'Clinical reason',
      helper:
          'Overrides never suppress warnings and are fully audited. '
          'Do not downgrade an emergency without direct clinical review.',
      maxLines: 3,
    );
    if (reason == null || !mounted) return;
    String outcome = _detail?.status ?? 'UNASSESSED';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirm override'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: outcome,
                  decoration: const InputDecoration(labelText: 'Final outcome'),
                  items:
                      const ['EMERGENCY', 'PRIORITY_REVIEW', 'ROUTINE_REVIEW']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.replaceAll('_', ' ')),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => outcome = value);
                  },
                ),
                const SizedBox(height: 14),
                const Text(
                  'I confirm this is an explicit clinical decision based on '
                  'reviewed evidence.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF647A86)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Set $outcome'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.api.post(
        '/api/cases/${widget.caseId}/override',
        body: {'final_status': outcome, 'reason': reason, 'confirmed': true},
      ),
      'Triage outcome overridden.',
    );
  }

  Future<void> _draftMessage() async {
    String intent = 'status_update';
    String language = 'en';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Draft patient message'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: intent,
                  decoration: const InputDecoration(
                    labelText: 'Message intent',
                  ),
                  items: _messageIntents.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => intent = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: language,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: _languages.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => language = value);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Only curated templates are used. A clinician must review '
                  'and approve the wording before delivery.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF647A86)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create draft'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    await _run(
      () => widget.api.post(
        '/api/cases/${widget.caseId}/communications/draft',
        body: {'intent': intent, 'language': language},
      ),
      'Message draft created for review.',
    );
  }

  Future<void> _messageAction(PatientMessage message, String action) async {
    final base = '/api/cases/${widget.caseId}/communications/${message.id}';
    if (action == 'approve') {
      final text = await _askText(
        title: 'Review and approve',
        label: 'Message text',
        initialValue: message.body,
        helper:
            'Edit the draft only to preserve accuracy and safety. '
            'Approval identity and time are audited.',
        maxLines: 5,
      );
      if (text == null) return;
      await _run(
        () => widget.api.post('$base/approve', body: {'text': text}),
        'Message approved.',
      );
    } else if (action == 'send') {
      await _run(() => widget.api.post('$base/send'), 'Delivery attempted.');
    } else if (action == 'dismiss') {
      final reason = await _askText(
        title: 'Dismiss message',
        label: 'Reason',
        helper: 'The draft remains in the audit trail but will not be sent.',
      );
      if (reason == null) return;
      await _run(
        () => widget.api.post('$base/dismiss', body: {'reason': reason}),
        'Message dismissed.',
      );
    }
  }

  Future<void> _syncFollowups() async {
    await _run(
      () => widget.api.post('/api/cases/${widget.caseId}/followups/sync'),
      'Follow-up suggestions synchronized.',
    );
  }

  Future<void> _followupAction(FollowUp followup, String action) async {
    final base = '/api/cases/${widget.caseId}/followups/${followup.id}';
    if (action == 'approve') {
      final text = await _askText(
        title: 'Approve follow-up question',
        label: 'Question text',
        initialValue: followup.text,
        helper: 'Staff approval is required before a follow-up is sent.',
        maxLines: 4,
      );
      if (text == null) return;
      await _run(
        () => widget.api.post(
          '$base/approve',
          body: {'text': text, 'language': followup.language},
        ),
        'Follow-up approved.',
      );
    } else if (action == 'send') {
      await _run(
        () => widget.api.post('$base/send'),
        'Follow-up delivery attempted.',
      );
    } else if (action == 'dismiss') {
      final reason = await _askText(
        title: 'Dismiss follow-up',
        label: 'Reason',
        helper:
            'The follow-up remains in the audit trail but will not be sent.',
      );
      if (reason == null) return;
      await _run(
        () => widget.api.post('$base/dismiss', body: {'reason': reason}),
        'Follow-up dismissed.',
      );
    } else if (action == 'answer') {
      final text = await _askText(
        title: 'Answer follow-up',
        label: 'Your answer',
        helper:
            'Your answer is linked to the question and may trigger '
            'reprocessing. It does not replace emergency care.',
        maxLines: 5,
      );
      if (text == null) return;
      await _run(
        () => widget.api.post(
          '$base/answers',
          body: {
            'text': text,
            'language': followup.language,
            'reprocess': true,
          },
        ),
        'Answer recorded and case reprocessed.',
      );
    }
  }

  Future<void> _acknowledge(Escalation escalation) async {
    final note = await _askText(
      title: 'Acknowledge escalation',
      label: 'Acknowledgement note',
      helper:
          'Acknowledging records operational receipt. It does not '
          'resolve the clinical emergency or its warning.',
      maxLines: 3,
    );
    if (note == null) return;
    await _run(
      () => widget.api.post(
        '/api/escalations/${escalation.id}/acknowledge',
        body: {'note': note},
      ),
      'Escalation acknowledged.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.caseId,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Case workspace',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF647A86)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh case',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (value) {
              if (value == 'consent') _grantConsent();
              if (value == 'source') _addSource();
              if (value == 'process') _process();
              if (value == 'assign') _assign();
              if (value == 'override') _override();
              if (value == 'sync') _syncFollowups();
              if (value == 'withdraw') _withdrawConsent();
            },
            itemBuilder: (context) => [
              if (_detail != null &&
                  !_detail!.hasConsent &&
                  !_detail!.isConsentWithdrawn)
                const PopupMenuItem(
                  value: 'consent',
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          size: 18, color: Color(0xFFE65100)),
                      SizedBox(width: 8),
                      Text('Grant consent'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'source',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Add intake / source'),
                  ],
                ),
              ),
              if (_staff)
                const PopupMenuItem(
                  value: 'process',
                  child: Text('Run processing'),
                ),
              if (_staff)
                const PopupMenuItem(
                  value: 'assign',
                  child: Text('Assign reviewer'),
                ),
              if (_staff)
                const PopupMenuItem(
                  value: 'override',
                  child: Text('Override outcome'),
                ),
              if (_staff)
                const PopupMenuItem(
                  value: 'sync',
                  child: Text('Sync follow-ups'),
                ),
              if (_detail != null && _detail!.hasConsent)
                const PopupMenuItem(
                  value: 'withdraw',
                  child: Text(
                    'Withdraw consent',
                    style: TextStyle(color: Color(0xFFB3261E)),
                  ),
                ),
            ],
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [ErrorPanel(_error!, onRetry: _load)],
            )
          : _buildDetail(_detail!),
    );
  }

  Widget _buildDetail(CaseDetail detail) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
        children: [
          _CaseHeader(
            detail: detail,
            staff: _staff,
            busy: _busy,
            onProcess: _process,
            onDraft: _draftMessage,
            onAssign: _assign,
            onOverride: _override,
            onGrantConsent: _grantConsent,
            onAddSource: _addSource,
          ),
          const SizedBox(height: 12),
          _consentCard(detail),
          const SizedBox(height: 12),
          _sourcesCard(detail),
          const SizedBox(height: 12),
          _urgencyCard(detail),
          if (detail.escalations.isNotEmpty) ...[
            const SizedBox(height: 12),
            _escalationsCard(detail),
          ],
          const SizedBox(height: 12),
          _summaryCard(detail),
          const SizedBox(height: 12),
          _communicationsCard(detail),
          const SizedBox(height: 12),
          _followupsCard(detail),
          const SizedBox(height: 12),
          _warningsCard(detail),
          const SizedBox(height: 12),
          _factsCard(detail),
        ],
      ),
    );
  }

  Widget _consentCard(CaseDetail detail) {
    if (detail.isConsentWithdrawn) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFDEcea),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF2BBB7)),
        ),
        child: const Row(
          children: [
            Icon(Icons.block_outlined, color: Color(0xFFB3261E), size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Consent Withdrawn',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Patient consent was withdrawn. AI pipeline processing and intake are suspended.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF647A86)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!detail.hasConsent) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFD54F)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFFF57F17), size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Patient Consent Required',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Explicit patient consent is required before clinical evidence can be ingested or analyzed by the CareFlow pipeline.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _grantConsent,
              icon: const Icon(Icons.check_circle_outline, size: 17),
              label: const Text('Grant patient consent'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Patient Consent Active',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                Text(
                  'Scope: ${detail.consentScope ?? 'careflow_processing_and_review'}',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF388E3C)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _withdrawConsent,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Withdraw', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _sourcesCard(CaseDetail detail) {
    return SectionCard(
      eyebrow: 'Direct intake evidence',
      title: 'Ingested sources (${detail.sources.length})',
      trailing: FilledButton.tonalIcon(
        onPressed: _busy ? null : _addSource,
        icon: const Icon(Icons.add_circle_outline, size: 17),
        label: const Text('Add source'),
      ),
      child: detail.sources.isEmpty
          ? Column(
              children: [
                const EmptyState(
                  'No sources ingested yet. Submit patient symptoms, history, or medical notes to provide raw clinical evidence.',
                  icon: Icons.source_outlined,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addSource,
                  icon: const Icon(Icons.post_add, size: 17),
                  label: const Text('Enter patient symptoms / details'),
                ),
              ],
            )
          : Column(
              children: detail.sources.map((source) {
                final modality = textValue(source['modality'], 'message');
                final snippet = textValue(
                  source['original_text'],
                  textValue(source['normalized_text'], 'Source captured.'),
                );
                final sourceId = textValue(source['source_id']);
                final captured = textValue(source['received_at']);

                IconData modalityIcon;
                switch (modality) {
                  case 'audio':
                    modalityIcon = Icons.mic_none;
                    break;
                  case 'document':
                    modalityIcon = Icons.document_scanner_outlined;
                    break;
                  case 'stt':
                    modalityIcon = Icons.graphic_eq;
                    break;
                  case 'ocr':
                    modalityIcon = Icons.receipt_long;
                    break;
                  default:
                    modalityIcon = Icons.chat_bubble_outline;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFB),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFFE1E9ED)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(modalityIcon, size: 16, color: careFlowTeal),
                          const SizedBox(width: 6),
                          Text(
                            modality.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: careFlowTeal,
                            ),
                          ),
                          const Spacer(),
                          if (sourceId.isNotEmpty)
                            Text(
                              sourceId.length > 16
                                  ? '${sourceId.substring(0, 16)}...'
                                  : sourceId,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFF647A86),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snippet,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Color(0xFF24363F),
                        ),
                      ),
                      if (captured.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Received: $captured',
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Color(0xFF647A86),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _escalationsCard(CaseDetail detail) {
    return SectionCard(
      eyebrow: 'Safety escalation',
      title: 'Urgent escalation',
      child: Column(
        children: detail.escalations.map((escalation) {
          final open = escalation.status != 'acknowledged';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFDEcea),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFF2BBB7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      size: 18,
                      color: Color(0xFFB3261E),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        escalation.triggerLabel.isEmpty
                            ? escalation.triggerCode
                            : escalation.triggerLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7D1C17),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    StatusChip(escalation.status),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${escalation.severity} · ${escalation.attempts} delivery '
                  'attempt(s) · ${formatTime(escalation.createdAt?.toIso8601String())}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF7D4C48),
                  ),
                ),
                if (escalation.lastError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Delivery issue: ${escalation.lastError}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                ],
                if (open && _staff) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _acknowledge(escalation),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Acknowledge receipt'),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _urgencyCard(CaseDetail detail) {
    final urgency = detail.urgency;
    return SectionCard(
      eyebrow: 'Advisory urgency · 0-100',
      title: 'Patient urgency',
      trailing: StatusChip(
        urgency == null ? 'not assessed' : '${urgency.score}/100',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (urgency == null)
            const Text(
              'Run processing to generate an advisory SLM assessment. '
              'The score never replaces clinician review or the workflow category.',
              style: TextStyle(fontSize: 12, color: Color(0xFF647A86)),
            )
          else ...[
            Text(urgency.rationale, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 6),
            Text(
              'Source: ${urgency.source}'
              '${urgency.model != null ? ' · model ${urgency.model}' : ''}'
              '${urgency.assessedAt != null ? ' · assessed ${formatTime(urgency.assessedAt!.toIso8601String())}' : ''}'
              '${urgency.editedBy != null ? ' · edited by ${urgency.editedBy}' : ''}',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF647A86)),
            ),
            if (urgency.editReason != null && urgency.editReason!.isNotEmpty)
              Text(
                'Edit reason: ${urgency.editReason}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF647A86),
                ),
              ),
          ],
          if (_staff &&
              detail.status != 'withdrawn' &&
              detail.status != 'deleted') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _editUrgency,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Edit urgency'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(CaseDetail detail) {
    final sections = mapList(detail.summary['sections']);
    final estimate = detail.queueEstimate;
    return SectionCard(
      eyebrow: 'Evidence-linked review',
      title: 'Care summary',
      trailing: StatusChip(detail.workflowStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.meta['assigned_reviewer'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Text(
                'Assigned reviewer: ${detail.meta['assigned_reviewer']}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (estimate != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 16,
                    color: Color(0xFF647A86),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Queue estimate: ${estimate.label}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF647A86),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (sections.isEmpty)
            const EmptyState(
              'No summary is available yet. Run processing after consent and '
              'ensure all intake information is present.',
              icon: Icons.description_outlined,
            )
          else
            ...sections.map((section) {
              final items = (section['items'] is List)
                  ? (section['items'] as List)
                        .map((item) => item.toString())
                        .toList()
                  : const <String>[];
              return Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            textValue(section['title'], 'Section'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          textValue(
                            section['epistemic_status'],
                            'unverified',
                          ).replaceAll('_', ' '),
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Color(0xFF647A86),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (items.isEmpty)
                      const Text(
                        'Not documented.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF647A86),
                        ),
                      )
                    else
                      ...items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '• ',
                                style: TextStyle(color: careFlowTeal),
                              ),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(fontSize: 12.2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _communicationsCard(CaseDetail detail) {
    return SectionCard(
      eyebrow: 'Patient communication',
      title: 'Messages',
      trailing: _staff
          ? FilledButton.tonalIcon(
              onPressed: _busy ? null : _draftMessage,
              icon: const Icon(Icons.edit_note, size: 17),
              label: const Text('Draft'),
            )
          : null,
      child: detail.messages.isEmpty
          ? const EmptyState(
              'No messages yet. Staff can draft a curated update for approval.',
              icon: Icons.mark_email_unread_outlined,
            )
          : Column(
              children: detail.messages
                  .map((message) => _messageTile(message))
                  .toList(),
            ),
    );
  }

  Widget _messageTile(PatientMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE1E9ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _messageIntents[message.intent] ??
                      message.intent.replaceAll('_', ' '),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusChip(message.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${message.language.toUpperCase()} · '
            '${formatTime(message.createdAt?.toIso8601String())}'
            '${message.delivery != null ? ' · ${message.delivery}' : ''}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF647A86)),
          ),
          const SizedBox(height: 7),
          Text(
            message.body,
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
          if (message.lastError != null) ...[
            const SizedBox(height: 5),
            Text(
              'Delivery issue: ${message.lastError}',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFB3261E)),
            ),
          ],
          if (_staff &&
              (message.status == 'draft' || message.status == 'approved')) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (message.status == 'draft')
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _messageAction(message, 'approve'),
                    child: const Text('Review & approve'),
                  ),
                if (message.status == 'approved')
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _messageAction(message, 'send'),
                    child: const Text('Send'),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _messageAction(message, 'dismiss'),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _followupsCard(CaseDetail detail) {
    return SectionCard(
      eyebrow: 'Adaptive follow-up',
      title: 'Follow-up questions',
      trailing: _staff
          ? FilledButton.tonalIcon(
              onPressed: _busy ? null : _syncFollowups,
              icon: const Icon(Icons.sync, size: 17),
              label: const Text('Sync'),
            )
          : null,
      child: detail.followups.isEmpty
          ? EmptyState(
              detail.workflowStatus == 'EMERGENCY'
                  ? 'Routine follow-up questions are suppressed because an EMERGENCY workflow status is active. Immediate clinical escalation takes priority.'
                  : 'No follow-up questions yet. Questions are generated from the reviewed summary and require staff approval.',
              icon: Icons.question_answer_outlined,
            )
          : Column(
              children: detail.followups.map((followup) {
                final answers = detail.answers
                    .where((answer) => answer.followupId == followup.id)
                    .toList();
                final canAnswer = followup.status == 'sent';
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFB),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFFE1E9ED)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              followup.text,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          StatusChip(followup.status),
                        ],
                      ),
                      if (followup.rationale.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          followup.rationale,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF647A86),
                          ),
                        ),
                      ],
                      if (followup.lastError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Delivery issue: ${followup.lastError}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFFB3261E),
                          ),
                        ),
                      ],
                      if (answers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...answers.map(
                          (answer) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 5),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFD8E3E8),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  answer.text,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${answer.role} · ${answer.answeredBy} · '
                                  '${formatTime(answer.createdAt?.toIso8601String())}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: Color(0xFF647A86),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if ((_staff &&
                              (followup.status == 'suggested' ||
                                  followup.status == 'draft' ||
                                  followup.status == 'approved')) ||
                          canAnswer) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            if (_staff && followup.status == 'suggested')
                              FilledButton.tonal(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          _followupAction(followup, 'approve'),
                                child: const Text('Review & approve'),
                              ),
                            if (_staff && followup.status == 'approved')
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _followupAction(followup, 'send'),
                                child: const Text('Send'),
                              ),
                            if (canAnswer)
                              FilledButton.tonal(
                                onPressed: _busy
                                    ? null
                                    : () => _followupAction(followup, 'answer'),
                                child: const Text('Answer'),
                              ),
                            if (_staff &&
                                (followup.status == 'suggested' ||
                                    followup.status == 'approved'))
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          _followupAction(followup, 'dismiss'),
                                child: const Text('Dismiss'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _warningsCard(CaseDetail detail) {
    return SectionCard(
      eyebrow: 'Safety findings',
      title: 'Warnings',
      child: detail.warnings.isEmpty
          ? const EmptyState(
              'No active safety warnings are recorded for this case.',
              icon: Icons.verified_outlined,
            )
          : Column(
              children: detail.warnings.map((warning) {
                final status = textValue(warning['status'], 'active');
                final color = statusColor(
                  textValue(warning['outcome'], status),
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: statusBackground(
                      textValue(warning['outcome'], status),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              textValue(warning['label'], 'Warning'),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                          Text(
                            status,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (textValue(warning['explanation']).isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          textValue(warning['explanation']),
                          style: TextStyle(
                            fontSize: 11,
                            color: color.withValues(alpha: .9),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _factsCard(CaseDetail detail) {
    return SectionCard(
      eyebrow: 'Source of truth',
      title: 'Structured facts',
      child: detail.facts.isEmpty
          ? const EmptyState(
              'No structured facts have been extracted yet.',
              icon: Icons.fact_check_outlined,
            )
          : Column(
              children: detail.facts.map((fact) {
                final value = fact['value'] ?? fact['value_normalized'] ?? '—';
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFEDF2F4)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              textValue(fact['label'], 'Fact'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$value${fact['unit'] != null ? ' ${fact['unit']}' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: careFlowNavy,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(
                        textValue(fact['verification_status'], 'unverified'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _CaseHeader extends StatelessWidget {
  const _CaseHeader({
    required this.detail,
    required this.staff,
    required this.busy,
    required this.onProcess,
    required this.onDraft,
    required this.onAssign,
    required this.onOverride,
    required this.onGrantConsent,
    required this.onAddSource,
  });

  final CaseDetail detail;
  final bool staff;
  final bool busy;
  final VoidCallback onProcess;
  final VoidCallback onDraft;
  final VoidCallback onAssign;
  final VoidCallback onOverride;
  final VoidCallback onGrantConsent;
  final VoidCallback onAddSource;

  @override
  Widget build(BuildContext context) {
    final emergency = detail.status == 'EMERGENCY';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: emergency
              ? const [Color(0xFF6E1714), Color(0xFF9E322A)]
              : const [careFlowNavy, Color(0xFF0D4B56)],
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
                      detail.status.replaceAll('_', ' '),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${detail.caseId} · ${detail.patientId}',
                      style: const TextStyle(
                        color: Color(0xFFC8DCE1),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  detail.workflowStatus.replaceAll('_', ' '),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (emergency) ...[
            const SizedBox(height: 10),
            const Text(
              'Emergency escalation must be handled by humans immediately. '
              'This workspace does not provide clinical clearance.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFFFFDAD6),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!detail.hasConsent && !detail.isConsentWithdrawn)
                FilledButton.icon(
                  onPressed: busy ? null : onGrantConsent,
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('Grant consent'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF57F17),
                    foregroundColor: Colors.white,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : onAddSource,
                icon: const Icon(Icons.add_circle_outline, size: 17),
                label: const Text('Add intake'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF47727D)),
                ),
              ),
              if (staff)
                FilledButton.icon(
                  onPressed: busy ? null : onProcess,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Run processing'),
                  style: FilledButton.styleFrom(
                    backgroundColor: careFlowMint,
                    foregroundColor: careFlowNavy,
                  ),
                ),
              if (staff)
                OutlinedButton.icon(
                  onPressed: busy ? null : onDraft,
                  icon: const Icon(Icons.edit_note, size: 17),
                  label: const Text('Draft message'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF47727D)),
                  ),
                ),
              if (staff)
                OutlinedButton.icon(
                  onPressed: busy ? null : onAssign,
                  icon: const Icon(Icons.person_add_alt, size: 17),
                  label: const Text('Assign'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF47727D)),
                  ),
                ),
              if (staff)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'override') onOverride();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'override',
                      child: Text('Override outcome'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0xFF47727D)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'More',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 3),
                        Icon(Icons.expand_more, color: Colors.white, size: 17),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
