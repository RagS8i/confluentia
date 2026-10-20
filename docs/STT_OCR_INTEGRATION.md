# STT and OCR integration

CareFlow does not run speech-to-text or OCR itself. It accepts the upstream component's output through JSON adapters that preserve provenance. Uploaded audio/PDF/images are stored encrypted as originals; text must be supplied through the STT/OCR endpoints (or the typed-message endpoint).

Endpoints:

- `POST /api/cases/{case_id}/sources/stt`
- `POST /api/cases/{case_id}/sources/ocr`
- `POST /api/cases/{case_id}/sources/message`

Consent is required. Ingesting the same payload twice is idempotent: stable source IDs are reported under `duplicates` instead of creating duplicate sources.

## STT payload

```json
{
  "transcript_id": "visit-123",
  "language": "hi",
  "language_status": "declared",
  "model": "your-stt-model",
  "confidence": 0.91,
  "captured_at": "2026-10-20T09:00:00Z",
  "segments": [
    {
      "text": "मुझे कल से बुखार है।",
      "start": 12.4,
      "end": 16.1,
      "confidence": 0.88,
      "language": "hi"
    }
  ]
}
```

Accepted aliases: `results` for `segments`; `transcript`/`text` for a single unsegmented transcript; `start_time`/`end_time` for `start`/`end`; `language_code`/`lang`; `recorded_at` for `captured_at`; `stt_model` for `model`; `id` for `transcript_id`.

Mapping:

- `transcript_id` -> `raw_metadata.transcript_id`, stable parent ID.
- `segments[i].text` -> original text (encrypted) and normalized text.
- `start`/`end` -> `SourceRef.audio_start`/`audio_end`.
- `confidence` -> source confidence; below 0.5 adds `low_source_confidence`.
- `language` -> declared language; script heuristics may add `language_metadata_mismatch` without overwriting metadata.
- Empty segments are skipped with notes; all-empty payloads are rejected with a 422-style `InputError`.

## OCR payload

```json
{
  "document_id": "lab-2026-10-20",
  "file_name": "report.pdf",
  "language": "en",
  "model": "your-ocr-model",
  "pages": [
    {
      "page": 1,
      "confidence": 0.93,
      "blocks": [
        {
          "text": "Temperature 101.5 F.",
          "bbox": [10, 20, 300, 42],
          "confidence": 0.95,
          "unreadable": false
        },
        {
          "text": "SpO2 ___ %",
          "bbox": [10, 50, 300, 72],
          "confidence": 0.31,
          "unreadable": true
        }
      ]
    }
  ]
}
```

Accepted aliases: `results` for `pages`; `lines` for `blocks`; `page_number` for `page`; `box` for `bbox`; top-level `text` for a single block; `filename` for `file_name`; `processed_at` for `captured_at`.

Mapping:

- Each block becomes a separate source with `page`, `bbox`, confidence and stable ID.
- `unreadable: true` adds `unreadable_critical_field`, which forces `critical_failure` and prevents a routine outcome.
- Low confidence adds `low_source_confidence`; the extractor additionally caps confidence and marks `low_extraction_confidence`.
- `document_id`/`file_name` is preserved as a document reference. It is not the same as an encrypted upload ID.

## Typed message payload

```json
{
  "text": "I have had a headache for two days.",
  "language": "en",
  "captured_at": "2026-10-20T10:00:00Z",
  "message_id": "msg-1",
  "confidence": 0.9
}
```

## Provenance expectations

Upstream components should send:

1. The **original** text, not just a cleaned version.
2. Stable transcript/document/segment IDs so retries deduplicate.
3. Segment timing for audio and page/bbox for documents, if available.
4. Per-segment confidence and declared language.
5. An explicit unreadable marker for critical fields the OCR could not read.

Do not send derived clinical conclusions from the STT/OCR component; send text and provenance only. Do not claim clinical accuracy for upstream models based on this integration.
