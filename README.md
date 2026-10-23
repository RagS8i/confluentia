# CareFlow AI

CareFlow AI is an open-source, local-first, human-in-the-loop clinical information coordination and triage-support platform. It processes multilingual clinical source material (speech-to-text audio transcripts, document OCR outputs, typed messages, and raw medical documents), extracts provenance-linked facts using a local Small Language Model (Qwen3-8B via Ollama), reconciles cross-source discrepancies and contradictions, applies a deterministic versioned triage rule set, computes an advisory 0–100 urgency score, and presents everything across a responsive **Web Workstation** and a cross-platform **Flutter Mobile Client**.

> [!WARNING]
> **Not a medical device. Not clinically validated.**
> The bundled triage rules and thresholds are illustrative demonstration configurations marked `ILLUSTRATIVE_DEMO_ONLY_NOT_CLINICALLY_APPROVED`. The system never diagnoses, prescribes, clears patients, or states that a patient does not require care. A qualified clinician must review and approve any rule set and every AI-generated output before real-world use. Do not use with real patient data without required clinical governance, privacy, security, and regulatory reviews.

---

## Architecture Overview

```
                                [ CLINICAL SOURCES ]
          +-----------------------+-----------------------+----------------------+
          |                       |                       |                      |
    Voice Audio (STT)      Medical Docs (OCR)       Typed Symptoms         Direct Uploads
   (Sarvam, in-process)  (GLM-OCR via Ollama)     (Patient / Intake)     (PDF, PNG, JPG)
          |                       |                       |                      |
          +-----------------------+-----------------------+----------------------+
                                  |
                                  v
                    [ INTAKE GATE & ADAPTERS ]
              Consent verification -> Normalization -> AES-Fernet Encryption
                                  |
                                  v
                      [ MULTI-STAGE SLM PIPELINE ]
               (Configurable Qwen3-8B / Gemma via local Ollama)
               Stage A: Text normalization & segment identification
               Stage B: Ambiguity detection & language reconciliation
               Stage C: Per-source structured clinical fact extraction (bounded retries)
               Stage D: Chronological timeline & temporal alignment
               Stage E: Cross-source contradiction & reconciliation matrix
                                  |
            +---------------------+---------------------+
            |                                           |
            v                                           v
[ DETERMINISTIC RULES ENGINE ]             [ CLINICAL SAFETY ESCALATION ]
 Independent rule evaluation               Immediate red-flag detection
 Priority categorization:                  Emergency webhook & outbox alerting
 * EMERGENCY (Immediate human care)        (Suppresses routine follow-ups)
 * PRIORITY_REVIEW
 * ROUTINE_REVIEW
 * UNASSESSED (Partial / uncertain)
            |
            +---------------------+---------------------+
                                  |
                                  v
                  [ ADVISORY COORDINATION SIGNALS ]
     * 0-100 Advisory Urgency Score (SLM + clinical override audit)
     * Conservative Queue Wait & Bottleneck Estimation
     * Adaptive Follow-Up Question Generation (Hindi / Hinglish / English)
     * Curated Pre-Approved Patient Communications
                                  |
         +------------------------+------------------------+
         |                                                 |
         v                                                 v
[ RESPONSIVE WEB WORKSTATION ]                 [ FLUTTER MOBILE APP ]
 Deployed: Vercel CDN                           Platform: Android / iOS / Desktop
 Runtime: Browser (HTML5/ES6/CSS3)              Runtime: Flutter 3.x / Dart 3.x
 Endpoint: Dynamic Backend Bridge               Config: In-app Settings & Tunnel
```

---

## Core Capabilities

1. **Direct Multimodal Intake**:
   - **Audio / STT**: Live in-browser microphone recording with timers or audio file upload (`.wav`, `.mp3`, `.m4a`). In-process translation via Sarvam AI API for English, Hindi, and Hinglish.
   - **Document OCR**: PDF and image uploads (lab reports, discharge summaries, prescriptions) converted to structured text via GLM-OCR running locally in Ollama.
   - **Typed Messages**: Structured patient intake for chief complaints, duration, vitals, and medical history.
2. **Provenance & Evidence Grounding**:
   - Every extracted clinical fact maintains strict quote attribution, source modality, segment ID, confidence score, and document bounding box coordinates or audio timestamps.
3. **Deterministic Safety Rules**:
   - Triage categories are evaluated by a deterministic, auditable JSON rule engine decoupled from the generative model. Unresolved or contradictory signals route to human review rather than being suppressed.
4. **Advisory Urgency Scoring (0–100)**:
   - Evaluated by the SLM across all consolidated evidence. Does not alter the deterministic triage category. Fully auditable: clinicians can edit the score with a mandatory recorded reason.
5. **Emergency Escalation Protocol**:
   - Emergency cases trigger immediate, deduplicated clinical escalations. Routine follow-up questions and non-urgent status messages are automatically suppressed to prioritize immediate clinical intervention.
6. **Adaptive Multilingual Follow-Up Questions**:
   - Detects informational gaps and suggests specific follow-up questions in English, Hindi, or Hinglish. Clinicians approve or dismiss questions before they are dispatched.
7. **Curated Patient Communications**:
   - Generates structured status, wait, and document-request notices based on approved clinical templates. Requires explicit staff sign-off before transmission.
8. **Operational Queue Intelligence**:
   - Calculates queue priority ordering, bottleneck tracking (waiting, overdue, unassigned cases), and conservative wait estimates based on observed review times and logged staffing capacity.
9. **Zero-Trust Data Protection**:
   - All sources, fact payloads, clinical summaries, notes, and uploaded documents are encrypted at rest with AES-Fernet. Supports GDPR/HIPAA-aligned consent withdrawal and irreversible deletion jobs.

---

## Deployment & Hosting Architecture

CareFlow AI is designed for flexible distributed deployment:
- **Backend**: Hosted locally on your workstation/laptop with local Ollama hardware acceleration. Exposed to remote clients via port forwarding or secure tunnels.
- **Web Frontend**: Deployed globally on **Vercel** serverless CDN (`https://static-five-ruby.vercel.app`), connecting dynamically to your local backend.
- **Mobile Client**: Runs natively on Android, iOS, or desktop, connecting directly to the local LAN IP or the forwarded tunnel URL.

```
       +---------------------------------------------+
       |           Vercel Global CDN                 |
       |  https://static-five-ruby.vercel.app        |
       +---------------------------------------------+
                             |
         Browser HTTP/HTTPS  | (Dynamic Backend Bridge)
                             v
                 +-----------------------+
                 | Port-Forward / Tunnel |
                 | (ngrok / Cloudflare)  |
                 +-----------------------+
                             |
                             v
       +---------------------------------------------+
       |        Your Laptop / Local Server           |
       |  FastAPI Backend (0.0.0.0:8000)             |
       |  SQLite (careflow.db) + AES-Fernet          |
       |  Ollama (127.0.0.1:11434) [Qwen3-8B]       |
       +---------------------------------------------+
                             ^
                             | Local LAN / Tunnel
       +---------------------------------------------+
       |         Flutter Mobile Client               |
       |  (Android / iOS / macOS / Windows)          |
       +---------------------------------------------+
```

---

## Quick Start & Local Setup

### Prerequisites
- Python 3.10+
- [Ollama](https://ollama.ai/) installed and running
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.12+ (for mobile)
- [FFmpeg](https://ffmpeg.org/) (for audio processing; install via `winget install Gyan.FFmpeg` on Windows)
- Vercel CLI (`npm install -g vercel`)

### 1. Backend Setup

```powershell
# Navigate to project root
cd d:\Confluentia

# Create and activate virtual environment
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Configure environment variables
Copy-Item .env.example .env
```

Generate a secure AES-Fernet encryption key:
```powershell
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```
Paste this key into `.env` as `CAREFLOW_ENCRYPTION_KEY=...`.

Pull the required Ollama models:
```powershell
ollama pull qwen3:8b
ollama pull glm-ocr
```

Start the CareFlow backend (listens on `0.0.0.0:8000` to allow local and tunnel access):
```powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```
Verify backend health:
```powershell
curl http://127.0.0.1:8000/api/health
```

---

## Port Forwarding (Exposing Backend to Web & Mobile)

To connect remote devices or the Vercel-hosted web client to your local backend, expose port `8000` using one of the following methods:

### Option A: ngrok (Recommended)
```powershell
ngrok http 8000
```
`ngrok` will provide a public HTTPS URL (e.g., `https://a1b2-c3d4.ngrok-free.app`).

### Option B: Cloudflare Tunnel
```powershell
cloudflared tunnel --url http://127.0.0.1:8000
```

### Option C: Local LAN (Same WiFi)
Find your laptop's local IPv4 address:
```powershell
ipconfig | findstr IPv4
# Example: 192.168.1.6
```
Your backend will be accessible at `http://192.168.1.6:8000`.

---

## Web Workstation Workflows

### Live Production Deployment (Vercel)
The web workstation is deployed to Vercel:
- **Production URL**: [https://static-five-ruby.vercel.app](https://static-five-ruby.vercel.app)
- **Local Fallback**: [http://127.0.0.1:8000/](http://127.0.0.1:8000/)

### Connecting the Vercel Web App to Your Backend
1. Open [https://static-five-ruby.vercel.app](https://static-five-ruby.vercel.app) in any desktop or mobile browser.
2. In the top navigation bar, locate the **Backend URL** input field.
3. Enter your port-forwarded tunnel address (e.g., `https://a1b2-c3d4.ngrok-free.app`) and click **Connect**.
4. The status pill will turn green: `online (qwen3:8b)`.
5. *(Optional)* You can also bookmark or share direct deep links with the parameter:
   ```
   https://static-five-ruby.vercel.app/?api=https://a1b2-c3d4.ngrok-free.app
   ```

### Deploying Your Own Web Frontend to Vercel
To redeploy updates directly from your machine:
```powershell
vercel app/static --yes --prod
```
The repository includes a preconfigured `app/static/vercel.json` with clean URL rewrites.

### Web Workstation Clinical Workflow
1. **Identity & Role Bar**:
   - Select your clinical role (`Clinician`, `Doctor`, `Nurse`, `Intake`, `Admin`, or `Patient`).
   - Development header authentication handles permissions automatically.
2. **Review Queue**:
   - Cases are prioritized by deterministic category (`EMERGENCY` > `PRIORITY_REVIEW` > `UNASSESSED` > `ROUTINE_REVIEW`).
   - Within categories, cases are sorted by advisory urgency score and waiting duration.
3. **Case Registration & Intake Consent**:
   - Click **"+ New Case"** to create a case.
   - Click **"Grant intake consent"** to record explicit patient consent for AI processing.
4. **Direct Source Intake**:
   - **Audio Tab**: Click **"Start recording"** to dictate clinical notes via browser microphone, choose target language (`English`, `Hindi`, `Hinglish`), and submit for Sarvam STT transcription.
   - **Document Tab**: Upload medical PDFs, lab slips, or images for GLM-OCR parsing.
   - **Message Tab**: Type patient symptoms, chief complaint, and history directly.
5. **Clinical Evidence & Fact Review**:
   - Inspect extracted facts with exact quote grounding.
   - Click any fact to **Verify**, **Correct**, **Dispute**, or **Reject**.
   - Review discrepancy warnings and contradictions across multiple sources.
6. **Clinical Summary & Note Approval**:
   - Review the auto-generated sectioned clinical summary.
   - Edit the unapproved draft clinical note and click **"Approve clinical note"**.
7. **Patient Communications & Follow-Ups**:
   - Review AI-suggested follow-up questions.
   - Draft and dispatch structured status updates to the patient in English or Hindi.

---

## Mobile Workflows (Flutter Client)

The Flutter mobile application (`mobile/`) provides clinicians and patients with a native mobile client for intake, triage review, and queue management.

### Running the Mobile App
```powershell
cd mobile
flutter pub get

# Run on connected device, emulator, or Windows desktop
flutter run
```

### Mobile Configuration & Connection
1. Open the app and navigate to **Settings** (bottom navigation tab).
2. Set the **Backend Base URL**:
   - **Android Emulator**: `http://10.0.2.2:8000`
   - **iOS Simulator / Local Desktop**: `http://127.0.0.1:8000`
   - **Physical Device (via Tunnel)**: `https://a1b2-c3d4.ngrok-free.app`
   - **Physical Device (via LAN)**: `http://192.168.1.6:8000`
3. Set your **User ID** and **Role** (`Clinician`, `Doctor`, `Nurse`, `Patient`, etc.).

### Mobile Clinical Workflows

#### 1. Case Registration & Direct Intake
- On the **Queue Screen**, tap the **`+` (New Case)** button.
- Enter the **Patient ID** and type **Initial Symptoms / Chief Complaint**.
- Leave **"Record patient consent"** and **"Run processing immediately"** toggled on.
- Tap **"Create & open"**: the case is registered, consent is documented, symptoms are ingested as raw evidence, and the pipeline runs triage extraction immediately.

#### 2. Consent Lifecycle Management
- In **CaseScreen**, a prominent **Consent Status Card** is displayed:
  - **Consent Required**: Displays an amber alert banner explaining that AI processing is held until consent is recorded, with a one-tap **"Grant patient consent"** button.
  - **Consent Active**: Displays a green badge with active scope details and a **"Withdraw"** button.
  - **Consent Revoked**: Alerts clinicians that processing and intake are suspended.
  - **Safety Auto-Prompt**: Tapping "Run processing" on an unconsented case prompts for one-tap consent recording and processing.

#### 3. Ingested Sources & Evidence Review
- The **Ingested Sources Card** lists all raw clinical material attached to the case.
- Badges denote source type (`MESSAGE`, `AUDIO`, `DOCUMENT`, `OCR`, `STT`) with timestamp and content preview.
- Tap **"+ Add Intake"** to record additional patient symptoms, vitals, or clinical progress notes on the fly.

#### 4. Urgency Score & Safety Escalations
- **Advisory Urgency Score Card**: Displays the 0–100 score calculated by the SLM with detailed clinical rationale.
- **Audited Urgency Override**: Clinicians can tap the edit icon to adjust the score with a mandatory recorded clinical reason.
- **Safety Escalation Banner**: If red flags (e.g., chest pain, severe dyspnea, critical vitals) are triggered, a critical red banner appears requiring human acknowledgement with a clinician note.

#### 5. Adaptive Follow-Up Questions & Patient Answers
- Tap **"Sync"** to generate follow-up questions from the summary.
- Clinicians can **Approve**, **Send**, or **Dismiss** questions.
- When logged in as **Patient**, questions can be answered directly; submitting an answer automatically triggers pipeline reprocessing with the new evidence.

#### 6. Curated Patient Messaging
- Tap **"Draft message"** to generate structured status updates, wait notifications, or document requests in English, Hindi, or Hinglish.
- Review drafts, make edits, and approve for outbound delivery.

#### 7. Operations & Staffing Dashboard
- Available for staff users in the **Operations** tab.
- Set active staffing numbers (`Clinicians available`, `Intake staff available`).
- Track queue bottlenecks (waiting cases, overdue cases, unassigned cases, open escalations).
- View conservative queue wait estimates with sample size indicators.

---

## API Reference

All `/api` endpoints except `/api/health` require authentication headers (`X-User-Id`, `X-Role`, and for patients `X-Patient-Id`).

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/health` | Service health, Ollama SLM status, active triage rules |
| `GET` | `/api/me` | Current authenticated principal |
| `POST` / `GET` | `/api/cases` | Register a new case / list review queue |
| `GET` | `/api/cases/{id}` | Complete case workspace payload |
| `GET` | `/api/cases/{id}/status` | Check processing status / polling target |
| `POST` | `/api/cases/{id}/consent` | Record patient intake & AI consent |
| `POST` | `/api/cases/{id}/consent/withdraw` | Withdraw consent & trigger optional deletion |
| `DELETE` | `/api/cases/{id}` | Irreversible case deletion job |
| `POST` | `/api/cases/{id}/sources/message` | Ingest typed symptoms / clinical notes |
| `POST` | `/api/cases/{id}/intake/audio` | Upload audio file for Sarvam STT & intake |
| `POST` | `/api/cases/{id}/intake/document` | Upload medical document for GLM-OCR parsing |
| `POST` | `/api/cases/{id}/process` | Trigger pipeline extraction (`?sync=true` for synchronous) |
| `PATCH` | `/api/cases/{id}/facts/{fact_id}` | Clinician fact verification / correction / dispute |
| `POST` | `/api/cases/{id}/warnings/{wid}/acknowledge` | Acknowledge clinical discrepancy warning |
| `PATCH` | `/api/cases/{id}/note` | Clinician draft note edit |
| `POST` | `/api/cases/{id}/note/approve` | Clinician formal note approval |
| `POST` | `/api/cases/{id}/override` | Override triage category with recorded reason |
| `POST` | `/api/cases/{id}/assign` | Assign named clinician reviewer |
| `PATCH` | `/api/cases/{id}/urgency` | Audited adjustment of advisory urgency score (0–100) |
| `GET` | `/api/cases/{id}/communications` | List curated patient communications |
| `POST` | `/api/cases/{id}/communications/draft` | Draft status/wait/document notice |
| `POST` | `/api/cases/{id}/communications/{mid}/approve` | Staff approval for outbound message |
| `POST` | `/api/cases/{id}/communications/{mid}/send` | Dispatch approved message |
| `GET` | `/api/cases/{id}/followups` | List adaptive follow-up questions |
| `POST` | `/api/cases/{id}/followups/sync` | Rebuild follow-up questions from clinical summary |
| `POST` | `/api/cases/{id}/followups/{fid}/approve` | Approve follow-up question |
| `POST` | `/api/cases/{id}/followups/{fid}/answers` | Submit patient answer & reprocess case |
| `GET` | `/api/escalations` | List safety escalations |
| `POST` | `/api/escalations/{id}/acknowledge` | Clinician emergency acknowledgement |
| `GET` / `PUT` | `/api/operations/staffing` | View / update operational staffing capacity |
| `GET` | `/api/queue/intelligence` | Queue triage priority rankings & bottleneck analytics |
| `GET` | `/api/cases/{id}/audit` | Full auditable event trail for governance |

---

## Testing & Quality Assurance

CareFlow maintains a 100% automated test pass rate across backend and mobile test suites:

```powershell
# 1. Run all backend tests (103 pytest tests)
pytest

# 2. Run Flutter unit & widget tests
cd mobile
flutter test

# 3. Run Flutter static analysis
flutter analyze
```

### Test Scope
- **Pipeline Cases**: Fact extraction, quote provenance, negation handling, temporal ordering.
- **Direct Intake**: Sarvam STT and GLM-OCR adapter integration, job queues, partial failures.
- **Security & RBAC**: Role verification across clinical roles (`doctor`, `nurse`, `clinician`, `admin`), patient scope isolation, consent enforcement.
- **Concurrency & Races**: Resumable deletion jobs, concurrent process locks, audit log integrity.
- **Mobile Client**: State models, queue intelligence parsing, consent serialization, status rendering.

---

## Repository Structure

```
.
├── app/                        # FastAPI core application
│   ├── main.py                 # API router, middleware, and entrypoint
│   ├── schemas.py              # Pydantic data schemas and models
│   ├── security.py             # Role-based access control & header auth
│   ├── db.py                   # SQLite database operations & audit logs
│   ├── storage.py              # AES-Fernet encryption at rest
│   ├── queue_ops.py            # Bottleneck calculation & wait estimation
│   ├── communications.py       # Curated messaging templates & approval
│   ├── followups.py            # Adaptive follow-up generator & answers
│   ├── escalation.py           # Urgent red-flag escalations
│   ├── pipeline/               # Multi-stage clinical extraction pipeline
│   ├── triage/                 # Deterministic JSON rule engine & demo rules
│   └── static/                 # Web review workstation (HTML/JS/CSS)
│       ├── index.html          # Web workstation UI
│       ├── app.js              # Workstation client & dynamic API bridge
│       ├── styles.css          # Design system & responsive layouts
│       └── vercel.json         # Vercel deployment configuration
├── mobile/                     # Cross-platform Flutter mobile client
│   ├── lib/
│   │   ├── main.dart           # App entrypoint
│   │   ├── api.dart            # HTTP client & error handler
│   │   ├── session.dart        # Session state & base URL configuration
│   │   ├── models.dart         # Strongly typed clinical models
│   │   ├── theme.dart          # CareFlow design system
│   │   ├── widgets.dart        # Shared UI components & chips
│   │   └── screens/
│   │       ├── home_shell.dart # Navigation shell
│   │       ├── queue_screen.dart # Triage queue & case creation modal
│   │       ├── case_screen.dart  # Case review, consent, sources, & summary
│   │       ├── operations_screen.dart # Staffing & bottleneck dashboard
│   │       └── settings_screen.dart   # Role & backend URL settings
│   └── test/                   # Flutter test suite
├── OCR1/                       # GLM-OCR model integration via Ollama
├── STT_translation/            # Sarvam Speech-to-Text audio integration
├── tests/                      # 103 pytest automated tests
├── docs/                       # Architecture and governance documentation
├── vercel.json                 # Root Vercel deployment configuration
└── careflow.db                 # SQLite database (auto-created)
```

---

## License & Governance

CareFlow AI is developed under the MIT License for research and demonstration purposes. All triage thresholds and safety rules must undergo formal institutional clinical governance prior to any production or clinical environment consideration.
