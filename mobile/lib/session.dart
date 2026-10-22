import 'dart:io';

import 'package:flutter/foundation.dart';

class CareFlowSession extends ChangeNotifier {
  CareFlowSession({
    String? baseUrl,
    this.userId = 'dr_mobile',
    this.role = 'clinician',
    this.patientId = 'patient_mobile',
  }) : baseUrl = baseUrl ?? defaultBaseUrl;

  static String get defaultBaseUrl {
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  String baseUrl;
  String userId;
  String role;
  String patientId;

  bool get isStaff =>
      role == 'clinician' ||
      role == 'doctor' ||
      role == 'nurse' ||
      role == 'physician' ||
      role == 'physician_assistant' ||
      role == 'nurse_practitioner' ||
      role == 'admin';
  bool get isPatient => role == 'patient';
  bool get canViewIntelligence => isStaff || role == 'intake';

  Map<String, String> get headers => {
    'X-User-Id': userId,
    'X-Role': role,
    if (isPatient) 'X-Patient-Id': patientId,
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  void update({
    required String baseUrl,
    required String userId,
    required String role,
    required String patientId,
  }) {
    this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    this.userId = userId.trim().isEmpty ? 'dr_mobile' : userId.trim();
    this.role = role;
    this.patientId = patientId.trim().isEmpty ? this.userId : patientId.trim();
    notifyListeners();
  }
}
