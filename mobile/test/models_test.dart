import 'package:careflow_app/models.dart';
import 'package:careflow_app/theme.dart';
import 'package:careflow_app/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queue intelligence parses recommendations and wait availability', () {
    final intelligence = QueueIntelligence.fromJson({
      'items': [
        {
          'case_id': 'case_123',
          'patient_id': 'patient_a',
          'workflow_status': 'EMERGENCY',
          'status': 'EMERGENCY',
          'received_at': '2026-10-20T10:00:00Z',
          'priority_rank': 1,
          'score': 98.5,
          'recommended_action': 'Immediate clinician review',
          'explanations': ['Emergency red flag present'],
          'factors': {'emergency': 100, 'overdue': 20},
          'overdue': true,
          'awaiting_minutes': 12,
          'wait_estimate': {
            'available': false,
            'basis': 'emergency case',
            'confidence': 'unavailable',
            'sample_size': 0,
            'disclaimer': 'No estimate for emergency cases.',
          },
        },
      ],
      'bottlenecks': {
        'total_waiting': 3,
        'overdue': 1,
        'unassigned': 2,
        'open_escalations': 1,
      },
      'staffing': {
        'clinicians_available': 2,
        'intake_available': 1,
        'average_review_minutes': 18.5,
        'sample_size': 8,
      },
      'disclaimer': 'Estimates are operational only.',
    });

    expect(intelligence.items, hasLength(1));
    expect(intelligence.items.first.priorityRank, 1);
    expect(
      intelligence.items.first.explanations.first,
      'Emergency red flag present',
    );
    expect(intelligence.items.first.waitEstimate?.available, isFalse);
    expect(intelligence.bottlenecks.openEscalations, 1);
    expect(intelligence.staffing.averageReviewMinutes, 18.5);
  });

  test('case detail parses communications, follow-ups, and escalations', () {
    final detail = CaseDetail.fromJson({
      'case': {
        'case_id': 'case_123',
        'patient_id': 'patient_a',
        'status': 'processed',
        'workflow_status': 'PRIORITY_REVIEW',
        'meta': {'assigned_reviewer': 'dr_a'},
        'consent_granted_at': '2026-10-20T10:00:00Z',
        'consent_scope': 'careflow_processing_and_review',
      },
      'communications': [
        {
          'message_id': 'msg_1',
          'intent': 'status_update',
          'language': 'en',
          'body': 'A clinician is reviewing your information.',
          'status': 'sent',
          'created_at': '2026-10-20T10:00:00Z',
        },
      ],
      'followups': [
        {
          'followup_id': 'fu_1',
          'text': 'How are your symptoms now?',
          'language': 'en',
          'status': 'sent',
          'addresses': ['current symptoms'],
          'rationale': 'Symptom change matters.',
        },
      ],
      'followup_answers': [
        {
          'answer_id': 'ans_1',
          'followup_id': 'fu_1',
          'text': 'Better than yesterday.',
          'answered_by': 'patient_a',
          'role': 'patient',
          'created_at': '2026-10-20T10:05:00Z',
        },
      ],
      'escalations': [
        {
          'escalation_id': 'esc_1',
          'trigger_code': 'RED_FLAG',
          'trigger_label': 'Emergency red flag',
          'status': 'sent',
          'severity': 'critical',
          'created_at': '2026-10-20T10:00:00Z',
          'attempts': 1,
        },
      ],
      'warnings': [],
      'facts': [],
      'summary': {'sections': []},
      'sources': [],
      'queue_estimate': null,
    });

    expect(detail.caseId, 'case_123');
    expect(detail.messages.single.status, 'sent');
    expect(detail.followups.single.addresses.single, 'current symptoms');
    expect(detail.answers.single.text, 'Better than yesterday.');
    expect(detail.escalations.single.triggerLabel, 'Emergency red flag');
    expect(detail.meta['assigned_reviewer'], 'dr_a');
    expect(detail.hasConsent, isTrue);
    expect(detail.consentScope, 'careflow_processing_and_review');
  });

  test('case summaries parse the paginated API envelope', () {
    final cases = caseSummariesFromResponse({
      'items': [
        {
          'case_id': 'case_patient',
          'patient_id': 'patient_a',
          'status': 'processed',
          'workflow_status': 'ROUTINE_REVIEW',
          'consent': 'granted',
          'overdue': false,
          'warning_count': 1,
        },
      ],
      'count': 1,
    });

    expect(cases, hasLength(1));
    expect(cases.single.caseId, 'case_patient');
    expect(cases.single.workflowStatus, 'ROUTINE_REVIEW');
    expect(cases.single.warningCount, 1);
  });

  testWidgets('status chip renders human-readable label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCareFlowTheme(),
        home: const Scaffold(body: StatusChip('PRIORITY_REVIEW')),
      ),
    );

    expect(find.text('PRIORITY REVIEW'), findsOneWidget);
  });
}
