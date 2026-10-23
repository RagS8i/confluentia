List<Map<String, dynamic>> mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<CaseSummary> caseSummariesFromResponse(dynamic value) {
  final map = mapValue(value);
  final items = map['items'];
  final source = items is List ? items : value;
  return mapList(source).map(CaseSummary.fromJson).toList();
}

Map<String, dynamic> mapValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

String textValue(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

int intValue(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(textValue(value)) ?? fallback;
}

double? doubleValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(textValue(value));
}

class Staffing {
  Staffing({
    this.cliniciansAvailable = 0,
    this.intakeAvailable = 0,
    this.averageReviewMinutes,
    this.sampleSize = 0,
    this.updatedBy,
    this.updatedAt,
  });

  final int cliniciansAvailable;
  final int intakeAvailable;
  final double? averageReviewMinutes;
  final int sampleSize;
  final String? updatedBy;
  final String? updatedAt;

  factory Staffing.fromJson(dynamic json) {
    final map = mapValue(json);
    return Staffing(
      cliniciansAvailable: intValue(map['clinicians_available']),
      intakeAvailable: intValue(map['intake_available']),
      averageReviewMinutes: doubleValue(map['average_review_minutes']),
      sampleSize: intValue(map['sample_size']),
      updatedBy: map['updated_by']?.toString(),
      updatedAt: map['updated_at']?.toString(),
    );
  }
}

class WaitEstimate {
  WaitEstimate({
    required this.available,
    this.minimumMinutes,
    this.maximumMinutes,
    this.basis = '',
    this.confidence = 'unavailable',
    this.sampleSize = 0,
    this.disclaimer = '',
  });

  final bool available;
  final int? minimumMinutes;
  final int? maximumMinutes;
  final String basis;
  final String confidence;
  final int sampleSize;
  final String disclaimer;

  factory WaitEstimate.fromJson(dynamic json) {
    final map = mapValue(json);
    return WaitEstimate(
      available: map['available'] == true,
      minimumMinutes: map['minimum_minutes'] == null
          ? null
          : intValue(map['minimum_minutes']),
      maximumMinutes: map['maximum_minutes'] == null
          ? null
          : intValue(map['maximum_minutes']),
      basis: textValue(map['basis']),
      confidence: textValue(map['confidence'], 'unavailable'),
      sampleSize: intValue(map['sample_size']),
      disclaimer: textValue(map['disclaimer']),
    );
  }

  String get label => available
      ? '$minimumMinutes–$maximumMinutes min · $confidence confidence'
      : 'Unavailable until staffing and sample data exist';
}

class UrgencyAssessment {
  UrgencyAssessment({
    required this.score,
    required this.rationale,
    required this.source,
    this.model,
    this.assessedAt,
    this.slmScore,
    this.editedBy,
    this.editReason,
  });

  final int score;
  final String rationale;
  final String source;
  final String? model;
  final DateTime? assessedAt;
  final int? slmScore;
  final String? editedBy;
  final String? editReason;

  factory UrgencyAssessment.fromJson(dynamic json) {
    final map = mapValue(json);
    return UrgencyAssessment(
      score: intValue(map['score']),
      rationale: textValue(map['rationale']),
      source: textValue(map['source'], 'unknown'),
      model: map['model']?.toString(),
      assessedAt: DateTime.tryParse(textValue(map['assessed_at'])),
      slmScore: map['slm_score'] == null ? null : intValue(map['slm_score']),
      editedBy: map['edited_by']?.toString(),
      editReason: map['edit_reason']?.toString(),
    );
  }
}

class Bottlenecks {
  Bottlenecks({
    this.totalWaiting = 0,
    this.overdue = 0,
    this.unassigned = 0,
    this.processingFailures = 0,
    this.emergency = 0,
    this.unassessed = 0,
    this.oldestWaitingMinutes,
    this.pendingCommunications = 0,
    this.pendingFollowups = 0,
    this.openEscalations = 0,
  });

  final int totalWaiting;
  final int overdue;
  final int unassigned;
  final int processingFailures;
  final int emergency;
  final int unassessed;
  final int? oldestWaitingMinutes;
  final int pendingCommunications;
  final int pendingFollowups;
  final int openEscalations;

  factory Bottlenecks.fromJson(dynamic json) {
    final map = mapValue(json);
    return Bottlenecks(
      totalWaiting: intValue(map['total_waiting']),
      overdue: intValue(map['overdue']),
      unassigned: intValue(map['unassigned']),
      processingFailures: intValue(map['processing_failures']),
      emergency: intValue(map['emergency']),
      unassessed: intValue(map['unassessed']),
      oldestWaitingMinutes: map['oldest_waiting_minutes'] == null
          ? null
          : intValue(map['oldest_waiting_minutes']),
      pendingCommunications: intValue(map['pending_communications']),
      pendingFollowups: intValue(map['pending_followups']),
      openEscalations: intValue(map['open_escalations']),
    );
  }
}

class QueueRecommendation {
  QueueRecommendation({
    required this.caseId,
    required this.patientId,
    required this.workflowStatus,
    required this.status,
    required this.receivedAt,
    required this.priorityRank,
    required this.score,
    required this.recommendedAction,
    required this.explanations,
    required this.factors,
    required this.overdue,
    this.awaitingMinutes,
    this.waitEstimate,
    this.urgencyScore,
    this.urgencySource,
  });

  final String caseId;
  final String patientId;
  final String workflowStatus;
  final String status;
  final DateTime? receivedAt;
  final int priorityRank;
  final double score;
  final String recommendedAction;
  final List<String> explanations;
  final Map<String, double> factors;
  final bool overdue;
  final int? awaitingMinutes;
  final WaitEstimate? waitEstimate;
  final int? urgencyScore;
  final String? urgencySource;

  factory QueueRecommendation.fromJson(Map<String, dynamic> json) {
    final factors = <String, double>{};
    mapValue(json['factors']).forEach((key, value) {
      final parsed = doubleValue(value);
      if (parsed != null) factors[key] = parsed;
    });
    return QueueRecommendation(
      caseId: textValue(json['case_id']),
      patientId: textValue(json['patient_id']),
      workflowStatus: textValue(json['workflow_status'], 'UNASSESSED'),
      status: textValue(json['status']),
      receivedAt: DateTime.tryParse(textValue(json['received_at'])),
      priorityRank: intValue(json['priority_rank'], 9),
      score: doubleValue(json['score']) ?? 0,
      recommendedAction: textValue(json['recommended_action']),
      explanations: json['explanations'] is List
          ? (json['explanations'] as List)
                .map((item) => item.toString())
                .toList()
          : const [],
      factors: factors,
      overdue: json['overdue'] == true,
      awaitingMinutes: json['awaiting_minutes'] == null
          ? null
          : intValue(json['awaiting_minutes']),
      waitEstimate: json['wait_estimate'] == null
          ? null
          : WaitEstimate.fromJson(json['wait_estimate']),
      urgencyScore: json['urgency_score'] == null
          ? null
          : intValue(json['urgency_score']),
      urgencySource: json['urgency_source']?.toString(),
    );
  }
}

class QueueIntelligence {
  QueueIntelligence({
    required this.items,
    required this.bottlenecks,
    required this.staffing,
    required this.disclaimer,
  });

  final List<QueueRecommendation> items;
  final Bottlenecks bottlenecks;
  final Staffing staffing;
  final String disclaimer;

  factory QueueIntelligence.fromJson(dynamic json) {
    final map = mapValue(json);
    return QueueIntelligence(
      items: mapList(map['items'])
          .map(QueueRecommendation.fromJson)
          .toList(growable: false),
      bottlenecks: Bottlenecks.fromJson(map['bottlenecks']),
      staffing: Staffing.fromJson(map['staffing']),
      disclaimer: textValue(map['disclaimer']),
    );
  }
}

class PatientMessage {
  PatientMessage({
    required this.id,
    required this.intent,
    required this.language,
    required this.body,
    required this.status,
    required this.createdAt,
    this.approvedBy,
    this.delivery,
    this.lastError,
  });

  final String id;
  final String intent;
  final String language;
  final String body;
  final String status;
  final DateTime? createdAt;
  final String? approvedBy;
  final String? delivery;
  final String? lastError;

  factory PatientMessage.fromJson(Map<String, dynamic> json) => PatientMessage(
    id: textValue(json['message_id']),
    intent: textValue(json['intent']),
    language: textValue(json['language']),
    body: textValue(json['body']),
    status: textValue(json['status']),
    createdAt: DateTime.tryParse(textValue(json['created_at'])),
    approvedBy: json['approved_by']?.toString(),
    delivery: json['delivery']?.toString(),
    lastError: json['last_error']?.toString(),
  );
}

class FollowUp {
  FollowUp({
    required this.id,
    required this.text,
    required this.language,
    required this.status,
    required this.addresses,
    required this.rationale,
    this.lastError,
  });

  final String id;
  final String text;
  final String language;
  final String status;
  final List<String> addresses;
  final String rationale;
  final String? lastError;

  factory FollowUp.fromJson(Map<String, dynamic> json) => FollowUp(
    id: textValue(json['followup_id']),
    text: textValue(json['text']),
    language: textValue(json['language']),
    status: textValue(json['status']),
    addresses: (json['addresses'] is List)
        ? (json['addresses'] as List).map((item) => item.toString()).toList()
        : const [],
    rationale: textValue(json['rationale']),
    lastError: json['last_error']?.toString(),
  );
}

class FollowUpAnswer {
  FollowUpAnswer({
    required this.id,
    required this.followupId,
    required this.text,
    required this.answeredBy,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String followupId;
  final String text;
  final String answeredBy;
  final String role;
  final DateTime? createdAt;

  factory FollowUpAnswer.fromJson(Map<String, dynamic> json) => FollowUpAnswer(
    id: textValue(json['answer_id']),
    followupId: textValue(json['followup_id']),
    text: textValue(json['text']),
    answeredBy: textValue(json['answered_by']),
    role: textValue(json['role']),
    createdAt: DateTime.tryParse(textValue(json['created_at'])),
  );
}

class Escalation {
  Escalation({
    required this.id,
    required this.triggerCode,
    required this.triggerLabel,
    required this.status,
    required this.severity,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });

  final String id;
  final String triggerCode;
  final String triggerLabel;
  final String status;
  final String severity;
  final DateTime? createdAt;
  final int attempts;
  final String? lastError;

  factory Escalation.fromJson(Map<String, dynamic> json) => Escalation(
    id: textValue(json['escalation_id']),
    triggerCode: textValue(json['trigger_code']),
    triggerLabel: textValue(json['trigger_label']),
    status: textValue(json['status']),
    severity: textValue(json['severity']),
    createdAt: DateTime.tryParse(textValue(json['created_at'])),
    attempts: intValue(json['attempts']),
    lastError: json['last_error']?.toString(),
  );
}

class CaseDetail {
  CaseDetail({
    required this.caseId,
    required this.patientId,
    required this.status,
    required this.workflowStatus,
    required this.meta,
    required this.messages,
    required this.followups,
    required this.answers,
    required this.escalations,
    required this.warnings,
    required this.facts,
    required this.summary,
    required this.sources,
    required this.queueEstimate,
    this.urgency,
    this.consentGrantedAt,
    this.consentScope,
    this.consentWithdrawnAt,
    this.note,
  });

  final String caseId;
  final String patientId;
  final String status;
  final String workflowStatus;
  final Map<String, dynamic> meta;
  final List<PatientMessage> messages;
  final List<FollowUp> followups;
  final List<FollowUpAnswer> answers;
  final List<Escalation> escalations;
  final List<Map<String, dynamic>> warnings;
  final List<Map<String, dynamic>> facts;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> sources;
  final WaitEstimate? queueEstimate;
  final UrgencyAssessment? urgency;
  final String? consentGrantedAt;
  final String? consentScope;
  final String? consentWithdrawnAt;
  final Map<String, dynamic>? note;

  bool get hasConsent => consentGrantedAt != null && consentWithdrawnAt == null;
  bool get isConsentWithdrawn => consentWithdrawnAt != null;

  factory CaseDetail.fromJson(dynamic json) {
    final data = mapValue(json);
    final caseMap = mapValue(data['case']);
    return CaseDetail(
      caseId: textValue(caseMap['case_id']),
      patientId: textValue(caseMap['patient_id']),
      status: textValue(caseMap['status']),
      workflowStatus: textValue(caseMap['workflow_status'], 'UNASSESSED'),
      meta: mapValue(caseMap['meta']),
      messages: mapList(data['communications'])
          .map(PatientMessage.fromJson)
          .toList(growable: false),
      followups: mapList(data['followups'])
          .map(FollowUp.fromJson)
          .toList(growable: false),
      answers: mapList(data['followup_answers'])
          .map(FollowUpAnswer.fromJson)
          .toList(growable: false),
      escalations: mapList(data['escalations'])
          .map(Escalation.fromJson)
          .toList(growable: false),
      warnings: mapList(data['warnings']),
      facts: mapList(data['facts']),
      summary: mapValue(data['summary']),
      sources: mapList(data['sources']),
      queueEstimate: data['queue_estimate'] == null
          ? null
          : WaitEstimate.fromJson(data['queue_estimate']),
      urgency: caseMap['urgency'] == null
          ? null
          : UrgencyAssessment.fromJson(caseMap['urgency']),
      consentGrantedAt: caseMap['consent_granted_at']?.toString(),
      consentScope: caseMap['consent_scope']?.toString(),
      consentWithdrawnAt: caseMap['consent_withdrawn_at']?.toString(),
      note: data['note'] == null ? null : mapValue(data['note']),
    );
  }
}

class CaseSummary {
  CaseSummary({
    required this.caseId,
    required this.patientId,
    required this.status,
    required this.workflowStatus,
    required this.consent,
    required this.overdue,
    this.awaitingMinutes,
    this.warningCount = 0,
    this.contradictionCount = 0,
    this.processingFailures = 0,
    this.assignedReviewer,
    this.urgencyScore,
    this.urgencySource,
  });

  final String caseId;
  final String patientId;
  final String status;
  final String workflowStatus;
  final String consent;
  final bool overdue;
  final int? awaitingMinutes;
  final int warningCount;
  final int contradictionCount;
  final int processingFailures;
  final String? assignedReviewer;
  final int? urgencyScore;
  final String? urgencySource;

  factory CaseSummary.fromJson(Map<String, dynamic> json) => CaseSummary(
    caseId: textValue(json['case_id']),
    patientId: textValue(json['patient_id']),
    status: textValue(json['status']),
    workflowStatus: textValue(json['workflow_status'], 'UNASSESSED'),
    consent: textValue(json['consent'], 'unknown'),
    overdue: json['overdue'] == true,
    awaitingMinutes: json['awaiting_minutes'] == null
        ? null
        : intValue(json['awaiting_minutes']),
    warningCount: intValue(json['warning_count']),
    contradictionCount: intValue(json['contradiction_count']),
    processingFailures: intValue(json['processing_failures']),
    assignedReviewer: json['assigned_reviewer']?.toString(),
    urgencyScore: json['urgency_score'] == null
        ? null
        : intValue(json['urgency_score']),
    urgencySource: json['urgency_source']?.toString(),
  );
}
