# CareFlow AI

CareFlow AI is a local-first, human-in-the-loop clinical information and triage-support prototype. It accepts synthetic or consented multilingual source material (STT transcripts, OCR output, typed messages, uploaded originals), extracts source-linked facts with a configurable small language model (Qwen3-8B via Ollama), reconciles cross-source differences, applies a deterministic versioned rule set, and presents everything for clinician review.

> **Not a medical device. Not clinically validated.** The bundled rules are illustrative demonstration thresholds marked `ILLUSTRATIVE_DEMO_ONLY_NOT_CLINICALLY_APPROVED`. The system never diagnoses, prescribes, clears a patient, or states that a patient does not need care. A qualified clinician must review and approve any rule set and every output before real-world use. Do not use with real patient data without the required privacy, security, clinical governance and regulatory review.

## What it does

- Ingests STT/OCR output through stable JSON adapters; preserves original text, language metadata, audio timestamps, page numbers and bounding boxes.
- Extracts facts per source with bounded retries, exact-quote attribution, negation/uncertainty handling and safe partial failure.
- Reconciles contradictions, historical-vs-current values, unit mismatches and potential duplicates without silently choosing a winner.
- Detects missing information and generates multilingual follow-up questions without inventing dates.
- Evaluates deterministic JSON rules independently of the SLM; unresolved/uncertain patterns route to human review instead of being suppressed.
- Produces an evidence-linked summary, gaps, warnings and an unapproved AI draft note.
- Supports clinician correction of facts, warning acknowledgement, note editing/approval, status override with reason, assignment and auditable review.
- Drafts curated patient messages in English, Hindi or Hinglish; requires staff approval before any delivery and never generates routine status messages for emergency cases.
- Explains queue ordering within each triage category, reports operational bottlenecks and only shows wait estimates when staffing and a sufficient observed sample are recorded.
- Generates persistent follow-up questions from the reviewed summary, requires staff approval, and reprocesses the case when an answer is recorded.
- Creates immediate, deduplicated emergency escalations before optional summaries or messages; delivery failures remain visible and retryable.
- Encrypts source text, fact payloads, message bodies, follow-up text, answers and uploaded documents at rest; supports consent withdrawal and resumable deletion jobs.
- Serves a responsive clinician review UI at `/` and includes a Flutter app in `mobile/` for queue, case, communication, follow-up and escalation workflows.

## Architecture

```
STT / OCR / typed message / upload
              |
       adapters + dedupe + encryption
              |
   Stage A normalize -> B language/ambiguity -> C per-source SLM extraction
              |                                      |
              |                            quote attribution + retries
              v
   D timeline -> E reconciliation -> F deterministic rules -> urgent escalation
              |                                      |
              |                                      v
              |                         G gaps/summary -> follow-up sync
              +---------------> website / Flutter <---+
                                  |
             fact correction / warning ack / note approval / override
             message draft / approve / send / dismiss
             follow-up approve / send / answer / dismiss
             escalation acknowledge / retry
```

Principal components:

- `app/main.py` - FastAPI app and API.
- `app/pipeline/` - normalization, interpretation, extraction, timeline, reconciliation, gaps, summary, orchestration.
- `app/model/` - Ollama and deterministic mock providers, prompts.
- `app/triage/` - rule engine and demo rule config.
- `app/queue_ops.py`, `app/communications.py`, `app/followups.py`, `app/escalation.py`, `app/outbound.py` - queue intelligence, curated messaging, adaptive follow-up, urgent escalation and delivery adapters.
- `app/db.py`, `app/storage.py`, `app/deletion.py` - SQLite persistence, encryption, deletion jobs.
- `app/security.py` - development header auth / API-key auth and case-level access control.
- `app/static/` - responsive dependency-free review and coordination UI.
- `mobile/` - Flutter client for Android and iOS.

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/STT_OCR_INTEGRATION.md](docs/STT_OCR_INTEGRATION.md), [docs/RULE_GOVERNANCE.md](docs/RULE_GOVERNANCE.md).

## Quick start (Windows PowerShell)

```powershell
cd D:\Confluentia
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt

Copy-Item .env.example .env
# Edit .env: set CAREFLOW_ENCRYPTION_KEY (see below), keep the mock provider for offline use:
#   CAREFLOW_LLM_PROVIDER=mock

# For Qwen instead of mock:
ollama pull qwen3:8b
# then set CAREFLOW_LLM_PROVIDER=ollama in .env

uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Generate an encryption key:

```powershell
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Open `http://127.0.0.1:8000/`. The UI uses development header auth by default; set `X-User-Id`, `X-Role` and (for patients) `X-Patient-Id` through the UI or API client.

### Flutter app

```powershell
cd mobile
flutter pub get
flutter run
```

The app defaults to `http://10.0.2.2:8000` on an Android emulator and `http://127.0.0.1:8000` on iOS. Physical devices need the host machine's LAN address. Configure the base URL, user ID, role and patient ID under **Settings**. The generated Android/iOS projects permit cleartext local HTTP for development only; use HTTPS and real authentication before any non-local deployment.

The Flutter client provides queue intelligence, operational bottlenecks and staffing, case review, curated message drafting/approval/send, follow-up approval/send/answer, and escalation acknowledgement. It applies the same role restrictions and safety boundaries as the API.

### Run tests

```powershell
python -m pytest -q
cd mobile
flutter test
flutter analyze
cd ..
```

```powershell
python -m pytest -q
```

Tests use `MockProvider`, temporary databases and synthetic text only. They do not call Ollama.

### Benchmark extraction (engineering metrics only)

```powershell
python scripts/benchmark_extraction.py --provider mock
python scripts/benchmark_extraction.py --provider ollama --model qwen3:8b
```

Reports are written to `reports/`. They measure schema validity, quote grounding, latency and label recall on a tiny synthetic set. They are **not** clinical validation and must not be described as accuracy.

### Validate a rule configuration

```powershell
python scripts/validate_rules.py
```

## Configuration

Configuration is read from environment variables and an optional `.env` file. See `.env.example` for all options. Key settings:

| Variable | Meaning |
| --- | --- |
| `CAREFLOW_LLM_PROVIDER` | `ollama` or `mock` (`mock` only for tests/offline demos) |
| `CAREFLOW_OLLAMA_MODEL` | Default `qwen3:8b` |
| `CAREFLOW_OLLAMA_BASE_URL` | Default `http://127.0.0.1:11434` |
| `CAREFLOW_ENCRYPTION_KEY` | Fernet key; if omitted a dev key is generated under `data/.careflow.key` |
| `CAREFLOW_PROCESSING_MODE` | `background` (default) or `sync` |
| `CAREFLOW_AUTH_MODE` | `dev` trusted headers or `api_key` |
| `CAREFLOW_RULES_PATH` | Rule JSON path |
| `CAREFLOW_MAX_UPLOAD_BYTES` | Upload limit, default 20 MiB |
| `CAREFLOW_COMMUNICATION_DELIVERY` | `outbox` (default), `webhook` or `fail` for drills |
| `CAREFLOW_ESCALATION_DELIVERY` | `outbox` (default), `webhook` or `fail` for drills |
| `CAREFLOW_OUTBOUND_WEBHOOK_URL` | Required when either delivery mode is `webhook` |
| `CAREFLOW_OUTBOUND_TIMEOUT_S` | Outbound request timeout, default 10 seconds |
| `CAREFLOW_WAIT_ESTIMATE_MIN_SAMPLE` | Minimum observed reviews before a wait estimate is allowed, default 3 |

The default model name is configurable; this project does not bundle weights. This machine may only have `gemma4:26b` installed, so pull `qwen3:8b` before expecting real SLM output. Model quality has not been evaluated.

## API overview

All `/api` routes except `/api/health` require authentication. In `dev` mode send `X-User-Id` and `X-Role` (`patient`, `intake`, `clinician`, `admin`); patients also send `X-Patient-Id`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/health` | Database, provider and rule-config status |
| `GET` | `/api/me` | Current principal |
| `POST` / `GET` | `/api/cases` | Create / list review queue |
| `GET` | `/api/cases/{id}` | Full case view |
| `GET` | `/api/cases/{id}/status` | Processing/review status and poll target |
| `POST` | `/api/cases/{id}/consent`, `/consent/withdraw` | Consent lifecycle |
| `DELETE` | `/api/cases/{id}` | Start deletion job |
| `POST` | `/api/cases/{id}/sources/stt`, `/ocr`, `/message` | Ingest structured sources |
| `POST` | `/api/cases/{id}/uploads` | Encrypted original upload (returns dedupe flag) |
| `GET` | `/api/documents/{document_id}` | Authorized, audited download |
| `POST` | `/api/cases/{id}/process` | Run pipeline (`?sync=true` for synchronous) |
| `PATCH` | `/api/cases/{id}/facts/{fact_id}` | Verify / correct / reject / dispute |
| `POST` | `/api/cases/{id}/warnings/{warning_id}/acknowledge` | Acknowledge warning |
| `PATCH` | `/api/cases/{id}/note` | Clinician edit |
| `POST` | `/api/cases/{id}/note/approve` | Approve note |
| `POST` | `/api/cases/{id}/override` | Override workflow status with reason |
| `POST` | `/api/cases/{id}/assign` | Assign reviewer (explicit confirmation required) |
| `GET` | `/api/communications/templates` | Curated templates by language |
| `POST` | `/api/cases/{id}/communications/draft` | Draft a curated status, wait, document, missing-information or urgent-review message |
| `GET` | `/api/cases/{id}/communications` | List messages (patients see sent messages only) |
| `POST` | `/api/cases/{id}/communications/{message_id}/approve`, `/send`, `/dismiss` | Message lifecycle |
| `GET` | `/api/cases/{id}/followups` | Follow-up questions and answers |
| `POST` | `/api/cases/{id}/followups/sync` | Rebuild follow-up suggestions from the summary |
| `POST` | `/api/cases/{id}/followups/{followup_id}/approve`, `/send`, `/dismiss` | Follow-up lifecycle |
| `POST` | `/api/cases/{id}/followups/{followup_id}/answers` | Record an answer and reprocess the case |
| `GET` / `PUT` | `/api/operations/staffing` | Read / update explicit operational capacity |
| `GET` | `/api/queue/intelligence` | Explainable ordering, bottlenecks and wait estimates |
| `GET` | `/api/escalations` | List urgent escalations by case/status |
| `POST` | `/api/escalations/{id}/acknowledge`, `/retry` | Acknowledge receipt or retry delivery |
| `GET` | `/api/cases/{id}/audit` | Audit trail (clinician/admin) |
| `GET` | `/api/deletion-jobs`, `POST /deletion-jobs/{id}/retry` | Admin deletion operations |
| `GET` | `/api/rules` | Rule config (clinician/admin) |

Workflow outcomes are `EMERGENCY`, `PRIORITY_REVIEW`, `UNASSESSED`, `ROUTINE_REVIEW`. `UNASSESSED` is used when information is insufficient, unreliable or processing failed; it is never a reassuring result. `ROUTINE_REVIEW` is a workflow queue label, not clinical clearance.

Example:

```powershell
$h = @{ "X-User-Id" = "dr_demo"; "X-Role" = "clinician" }
$case = Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/api/cases `
  -Headers $h -ContentType "application/json" -Body '{"patient_id":"patient_demo"}'
$id = $case.case_id
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8000/api/cases/$id/consent" `
  -Headers @{ "X-User-Id"="intake_demo"; "X-Role"="intake" } `
  -ContentType "application/json" -Body '{"scope":"demo"}'
```

Consent must be granted before ingestion/processing. In the demo, `intake` or `admin` can grant it; patients grant their own consent.

## Data handling

- SQLite in `CAREFLOW_DATA_DIR`; uploaded blobs under `data/uploads/` encrypted with Fernet.
- Source text, derived fact payloads, message bodies, follow-up questions, answers and uploads are encrypted. Audit metadata (who did what) is separate and retained after deletion for accountability.
- Default delivery writes to an auditable outbox rather than contacting a real patient channel. Webhook delivery is opt-in and must be configured with an approved endpoint.
- Uploads are validated by MIME/size and deduplicated by SHA-256 per case.
- Withdrawal/deletion removes sources, facts, derived summaries and documents via idempotent, resumable jobs. The processing loop re-checks deletion/withdrawal before persisting derived data.
- The service stores no real patient data by default and has no telemetry.

## Limitations and non-goals

- Not a diagnosis, prescription, disposition or clinical-clearance system; no autonomous patient-facing advice.
- Demo thresholds are not an approved triage protocol and have not been clinically validated.
- STT/OCR are external; this repo provides integration adapters, not speech/image models. Do not fabricate confidence or clinical accuracy metrics.
- Patient messages are curated templates, not generative clinical advice. Only `en`, `hi` and `hinglish` variants exist; missing variants fail safely rather than being machine-translated at runtime.
- Wait estimates are operational estimates, not guarantees. They are unavailable for emergency cases and when staffing, review-time data or the minimum sample is missing.
- Follow-up suggestions do not replace clinician review, emergency escalation or direct communication.
- No production identity provider, TLS termination, rate limiting, HA database, backup/restore or regulatory controls. `dev` header auth is for local demos only.
- Single-node SQLite; background jobs are in-process only.
- Qwen3-8B on a 6 GB laptop GPU may be slow or spill to CPU; tune `CAREFLOW_OLLAMA_NUM_GPU`, `NUM_CTX` and timeout, and verify with `/api/health`.
- Python 3.10 is used; adjust dependency pins if deploying elsewhere.

## Repository layout

```
app/                 FastAPI app, pipeline, model providers, rules, website
mobile/              Flutter client (Android/iOS)
tests/               pytest suite (synthetic data, mock provider)
scripts/             extraction benchmark, rule-config validator
docs/                architecture, integration and governance notes
data/                runtime data (gitignored)
reports/             generated benchmark reports (gitignored)
```
