"""Integration tests for OCR1 and STT_translation modules with CareFlow adapters."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.pipeline.normalize import InputError, adapt_ocr, adapt_stt
from OCR1.schemas import OcrDocument, OcrPage
from OCR1.ocr_text import ocr_document_to_text
from STT_translation.schemas import (
    Language,
    SpeechTranslationInput,
    SpeechTranslationRequest,
    SpeechTranslationResult,
    TranscriptChunk,
)
from OCR1.api import app as ocr_app
from STT_translation.api import app as stt_app


def test_ocr1_schemas_and_text_extraction():
    """Verify OCR1 schemas and layout text extraction."""
    payload = {
        "file_name": "lab_report.pdf",
        "page_count": 1,
        "pages": [
            {
                "page_number": 1,
                "model_output": {
                    "res": {
                        "parsing_res_list": [
                            {
                                "block_label": "text",
                                "block_content": "Patient Name: Jane Doe",
                                "block_order": 1,
                                "bbox": [10, 10, 100, 20],
                                "confidence": 0.98,
                            },
                            {
                                "block_label": "table",
                                "block_content": "Hemoglobin | 11.2 g/dL | Low",
                                "block_order": 2,
                                "bbox": [10, 30, 200, 80],
                                "confidence": 0.94,
                            },
                            {
                                "block_label": "image",
                                "block_content": "binary-seal-data",
                                "block_order": 3,
                            },
                        ]
                    }
                },
            }
        ],
    }

    doc = OcrDocument.model_validate(payload)
    assert doc.file_name == "lab_report.pdf"
    assert doc.page_count == 1
    assert len(doc.pages) == 1

    extracted_text = ocr_document_to_text(doc)
    assert "Patient Name: Jane Doe" in extracted_text
    assert "Hemoglobin | 11.2 g/dL | Low" in extracted_text
    assert "binary-seal-data" not in extracted_text


def test_stt_translation_schemas():
    """Verify STT_translation schemas validate correctly."""
    req = SpeechTranslationRequest(target_language=Language.ENGLISH)
    assert req.target_language == "en-IN"

    inp = SpeechTranslationInput(filename="cough_audio.wav", target_language=Language.ENGLISH)
    assert inp.filename == "cough_audio.wav"

    chunk = TranscriptChunk(
        index=0,
        start_seconds=1.2,
        end_seconds=4.5,
        translated_text="I have had persistent chest pain and cough for three days.",
        language_code="hi",
        language_probability=0.92,
    )
    result = SpeechTranslationResult(
        translated_text="I have had persistent chest pain and cough for three days.",
        target_language="en-IN",
        chunks=[chunk],
    )
    assert result.chunks[0].translated_text == chunk.translated_text
    assert result.chunks[0].start_seconds == 1.2


def test_adapt_stt_with_stt_translation_result():
    """Verify CareFlow Stage A adapt_stt seamlessly consumes STT_translation results."""
    stt_payload = {
        "translated_text": "I have had fever and chills since yesterday.",
        "target_language": "en-IN",
        "chunks": [
            {
                "index": 0,
                "start_seconds": 0.5,
                "end_seconds": 3.8,
                "translated_text": "I have had fever and chills since yesterday.",
                "language_code": "hi",
                "language_probability": 0.91,
            }
        ],
    }

    records, notes = adapt_stt(stt_payload, case_id="case_test_stt_001")
    assert not notes
    assert len(records) == 1
    rec = records[0]
    assert rec.audio_start == 0.5
    assert rec.audio_end == 3.8
    assert rec.language == "hi"
    assert rec.confidence == 0.91
    assert "fever and chills" in rec.normalized_text


def test_adapt_ocr_with_ocr1_result():
    """Verify CareFlow Stage A adapt_ocr seamlessly consumes OCR1 results."""
    ocr_payload = {
        "file_name": "patient_vitals.pdf",
        "page_count": 1,
        "pages": [
            {
                "page_number": 1,
                "model_output": {
                    "res": {
                        "parsing_res_list": [
                            {
                                "block_label": "text",
                                "block_content": "Blood Pressure: 150/95 mmHg",
                                "block_order": 1,
                                "bbox": [50, 50, 250, 80],
                                "confidence": 0.96,
                            },
                            {
                                "block_label": "text",
                                "block_content": "Pulse: 104 bpm",
                                "block_order": 2,
                                "block_bbox": [50, 90, 200, 120],
                            },
                        ]
                    }
                },
            }
        ],
    }

    records, notes = adapt_ocr(ocr_payload, case_id="case_test_ocr_001")
    assert not notes
    assert len(records) == 2
    assert records[0].page == 1
    assert "Blood Pressure: 150/95 mmHg" in records[0].normalized_text
    assert records[0].confidence == 0.96
    assert records[1].page == 1
    assert "Pulse: 104 bpm" in records[1].normalized_text
    assert records[1].bbox == [50.0, 90.0, 200.0, 120.0]


def test_ocr1_health_and_validation():
    """Verify OCR1 API health endpoint and input validation."""
    client = TestClient(ocr_app)
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}

    # Unsupported extension rejection
    bad_upload = client.post(
        "/ocr",
        files={"file": ("notes.txt", b"plain text is unsupported", "text/plain")},
    )
    assert bad_upload.status_code == 415

    # Empty file rejection
    empty_upload = client.post(
        "/ocr",
        files={"file": ("blank.pdf", b"", "application/pdf")},
    )
    assert empty_upload.status_code == 400


def test_stt_translation_health_and_validation():
    """Verify STT_translation API health endpoint and input validation."""
    client = TestClient(stt_app)
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}

    # Empty audio rejection
    empty_upload = client.post(
        "/speech-to-language",
        files={"audio": ("empty.wav", b"", "audio/wav")},
    )
    assert empty_upload.status_code == 400

def test_adapters_reject_payloads_with_no_usable_text():
    """All-empty OCR/STT payloads must fail rather than enqueue an empty case."""
    with pytest.raises(InputError) as stt_error:
        adapt_stt(
            {"transcript_id": "empty-stt", "segments": [{"text": "   "}]},
            case_id="case_empty_stt",
        )
    assert stt_error.value.code == "empty_transcript"

    with pytest.raises(InputError) as ocr_error:
        adapt_ocr(
            {
                "document_id": "empty-ocr",
                "pages": [{"page": 1, "blocks": [{"text": "\n\t"}]}],
            },
            case_id="case_empty_ocr",
        )
    assert ocr_error.value.code == "empty_document"


def test_adapt_stt_preserves_original_hindi_and_hinglish_provenance():
    """Regression test: Hindi/Hinglish transcription survives in original_text, not replaced by translation."""
    hindi_payload = {
        "transcription": "मुझे दो दिन से चक्कर आ रहे हैं और बहुत कमजोरी लग रही है",
        "translated_text": "I have been feeling dizzy and very weak for two days",
        "target_language": "en-IN",
        "document_id": "doc_hindi_audio_001",
        "chunks": [
            {
                "index": 0,
                "start_seconds": 1.0,
                "end_seconds": 4.5,
                "transcription": "मुझे दो दिन से चक्कर आ रहे हैं और बहुत कमजोरी लग रही है",
                "translated_text": "I have been feeling dizzy and very weak for two days",
                "language_code": "hi",
                "language_probability": 0.98,
            }
        ],
    }

    records, notes = adapt_stt(hindi_payload, case_id="case_hindi_001")
    assert not notes
    assert len(records) == 1
    rec = records[0]
    # PROVENANCE CHECK: original_text MUST be the Hindi transcription!
    assert "मुझे दो दिन से चक्कर आ रहे हैं" in rec.original_text
    assert "feeling dizzy" not in rec.original_text
    # English translation preserved in raw_metadata
    assert rec.raw_metadata.get("translated_text") == "I have been feeling dizzy and very weak for two days"
    assert rec.document_ref == "doc_hindi_audio_001"
    assert rec.audio_start == 1.0
    assert rec.audio_end == 4.5
    assert rec.language == "hi"

    # Hinglish provenance test
    hinglish_payload = {
        "transcription": "Mujhe two days se sudden chest pain ho raha hai after walking",
        "translated_text": "I have sudden chest pain for two days after walking",
        "target_language": "en-IN",
        "document_id": "doc_hinglish_001",
        "chunks": [
            {
                "index": 0,
                "start_seconds": 0.0,
                "end_seconds": 3.8,
                "transcription": "Mujhe two days se sudden chest pain ho raha hai after walking",
                "translated_text": "I have sudden chest pain for two days after walking",
                "language_code": "hinglish",
                "language_probability": 0.92,
            }
        ],
    }
    records, notes = adapt_stt(hinglish_payload, case_id="case_hinglish_001")
    assert len(records) == 1
    h_rec = records[0]
    assert "Mujhe two days se sudden chest pain" in h_rec.original_text
    assert h_rec.document_ref == "doc_hinglish_001"
    assert h_rec.language == "hinglish"


def test_adapt_ocr_with_paddle_model_output():
    """Verify adapt_ocr extracts structured blocks and bboxes directly from Paddle model_output."""
    payload = {
        "document_id": "doc_lab_002",
        "file_name": "patient_lab_report.pdf",
        "page_count": 1,
        "pages": [
            {
                "page_number": 1,
                "model_output": {
                    "res": {
                        "parsing_res_list": [
                            {
                                "block_label": "text",
                                "block_content": "Fasting Blood Sugar: 145 mg/dL",
                                "block_order": 1,
                                "bbox": [15.0, 25.0, 190.0, 45.0],
                                "confidence": 0.99,
                            },
                            {
                                "block_label": "text",
                                "block_content": "HbA1c: 7.8 % (High)",
                                "block_order": 2,
                                "block_bbox": [15.0, 55.0, 160.0, 75.0],
                                "confidence": 0.98,
                            },
                        ]
                    }
                },
            }
        ],
    }

    records, notes = adapt_ocr(payload, case_id="case_paddle_001")
    assert not notes
    assert len(records) == 2
    r0 = records[0]
    assert r0.document_ref == "doc_lab_002"
    assert "Fasting Blood Sugar: 145 mg/dL" in r0.original_text
    assert r0.bbox == [15.0, 25.0, 190.0, 45.0]
    assert r0.page == 1

    r1 = records[1]
    assert "HbA1c: 7.8 %" in r1.original_text
    assert r1.bbox == [15.0, 55.0, 160.0, 75.0]

