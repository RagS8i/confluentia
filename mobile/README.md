# CareFlow AI mobile

Flutter client for the CareFlow AI coordination API.

## Run

```powershell
flutter pub get
flutter run
```

Default server addresses:

- Android emulator: `http://10.0.2.2:8000`
- iOS simulator: `http://127.0.0.1:8000`
- Physical device: use the host machine's LAN address

Set the base URL, user ID, role and patient ID under **Settings**. The default
development identity is `dr_mobile` with role `clinician`. In `dev` auth mode the
app sends `X-User-Id`, `X-Role` and, for patients, `X-Patient-Id`.

## Features

- Explainable queue priorities and bottleneck metrics for staff.
- Personal case list for patients.
- Case review with warnings, facts, summary and queue estimate.
- Curated message draft, approval, send and dismiss.
- Follow-up approval, send, answer and dismiss.
- Emergency escalation acknowledgement.
- Staffing assumptions and wait-estimate inputs.

## Safety

This is not a medical device. Demo triage rules are illustrative and not
clinically approved. The app does not diagnose, prescribe, clear a patient, or
replace emergency care. Messages and follow-ups require staff approval before
delivery.

Cleartext HTTP is enabled in the generated Android and iOS projects for local
development only. Before any non-local deployment, use HTTPS, real
authentication, and a reviewed security configuration.

## Verify

```powershell
flutter analyze
flutter test
```
