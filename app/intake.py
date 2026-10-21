"""Direct audio and document intake services for CareFlow AI.

Provides an in-process STT runner (Sarvam ``speech_to_language``), an async OCR
client, an in-process intake job registry, and lifecycle handling from upload to
background extraction, persistence, and pipeline submission.
"""
from __future__ import annotations

import asyncio
import logging
import mimetypes
import tempfile
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Protocol

import httpx
from fastapi.concurrency import run_in_threadpool

from STT_translation.errors import (
    AudioDecodeError,
    SpeechTranslationError,
    TranscriptionError,
    TranslationError,
)

from .config import Settings
from .db import Database
from .pipeline.normalize import InputError, adapt_ocr, adapt_stt
from .pipeline.orchestrator import PipelineService
from .schemas import CaseRecord, CaseStatus, SourceRecord
from .security import Principal
from .storage import Cipher, DocumentStore, random_id, safe_error

logger = logging.getLogger("careflow.intake")


class SttTimeoutError(RuntimeError):
    """CareFlow stopped waiting for the local speech-to-language worker.

    The worker thread cannot be forcibly stopped, so a Sarvam request may keep
    running after this error is raised; the result is discarded.
    """


def safe_intake_error(exc: Exception) -> str:
    """Return a safe, retryable error message for intake failures."""
    if isinstance(exc, SttTimeoutError):
        return "Speech processing timed out. Please retry."
    if isinstance(exc, AudioDecodeError):
        return (
            "Audio could not be decoded. Supported formats: "
            "WAV, MP3, M4A, OGG, FLAC, WebM."
        )
    if isinstance(exc, TranscriptionError):
        return "Speech transcription failed. Please retry."
    if isinstance(exc, TranslationError):
        return "Transcript translation failed. Please retry."
    if isinstance(exc, SpeechTranslationError):
        return "Speech processing failed. Please retry."
    if isinstance(exc, httpx.TimeoutException):
        return "Service connection timed out. Please retry."
    if isinstance(exc, httpx.ConnectError):
        return "Could not connect to intake service. Ensure service is running and retry."
    if isinstance(exc, httpx.HTTPStatusError):
        return f"Intake service returned HTTP {exc.response.status_code}. Please retry."
    if isinstance(exc, InputError):
        return f"Input error: {exc.message}"
    if isinstance(exc, RuntimeError):
        return f"{exc}"
    return safe_error(exc)


# -----------------------------------------------------------------------------
# Persistence & Audit Helper (shared between JSON routes and background intake)
# -----------------------------------------------------------------------------

def persist_sources(
    db: Database,
    cipher: Cipher,
    case: CaseRecord,
    sources: List[SourceRecord],
    notes: List[str],
    user_id: str,
    role: str,
    kind: str,
) -> Dict[str, Any]:
    """Persist normalized sources, advance case status if appropriate, and write audit trail.

    Shared by synchronous JSON routes and background intake tasks.
    """
    if not case.consent_granted:
        raise ValueError("Consent required for ingestion")

    inserted: List[str] = []
    duplicates: List[str] = []
    for source in sources:
        if db.upsert_source(source, cipher):
            inserted.append(source.source_id)
        else:
            duplicates.append(source.source_id)

    refreshed = db.get_case(case.case_id, include_deleted=True)
    if refreshed is not None and not refreshed.deleted and refreshed.status in (CaseStatus.received, CaseStatus.consent_pending):
        refreshed.status = CaseStatus.queued
        db.save_case(refreshed)

    db.audit(
        user_id,
        role,
        f"{kind}_ingested",
        case.case_id,
        {
            "inserted": len(inserted),
            "duplicates": len(duplicates),
            "notes": notes,
            "modalities": sorted({s.modality.value for s in sources}),
        },
    )

    return {
        "case_id": case.case_id,
        "inserted": inserted,
        "duplicates": duplicates,
        "notes": notes,
        "sources": [s.source_id for s in sources],
    }


# -----------------------------------------------------------------------------
# Intake services: in-process STT, optional HTTP OCR
# -----------------------------------------------------------------------------

class SttService(Protocol):
    """Minimal interface required by IntakeService for audio transcription."""

    async def transcribe(
        self,
        audio_bytes: bytes,
        filename: str = "audio.wav",
        target_language: str = "en-IN",
    ) -> Dict[str, Any]: ...


def _run_speech_to_language(
    audio_bytes: bytes,
    target_language: str,
    filename: str,
) -> Dict[str, Any]:
    """Run the repository's Sarvam implementation synchronously.

    Imported lazily so CareFlow can start (and unit tests can run) without the
    Sarvam SDK, ffmpeg or an API key unless audio intake is actually used.
    """
    from STT_translation.stt import speech_to_language

    return speech_to_language(
        audio_bytes=audio_bytes,
        target_language=target_language,
        filename=filename,
    )


class LocalSttService:
    """Calls ``STT_translation.stt.speech_to_language`` in a worker thread.

    CareFlow's web intake path uses this instead of HTTP to port 8001. The
    standalone FastAPI service (``STT_translation/api.py``) remains available
    for external callers and uses the same underlying function.
    """

    def __init__(self, timeout_s: float = 120.0):
        self.timeout_s = timeout_s

    async def transcribe(
        self,
        audio_bytes: bytes,
        filename: str = "audio.wav",
        target_language: str = "en-IN",
    ) -> Dict[str, Any]:
        """Return the structured transcription/translation result.

        Transcription is CPU/IO bound (ffmpeg decode plus blocking Sarvam SDK
        calls), so it runs via ``asyncio.to_thread``. ``wait_for`` only bounds
        how long CareFlow waits; it cannot cancel the thread's network request.
        """
        try:
            return await asyncio.wait_for(
                asyncio.to_thread(
                    _run_speech_to_language,
                    audio_bytes,
                    target_language,
                    filename,
                ),
                timeout=self.timeout_s,
            )
        except asyncio.TimeoutError as exc:
            raise SttTimeoutError(
                "local speech-to-language processing exceeded the configured timeout"
            ) from exc


class OcrClient:
    """Async client for the CareFlow OCR service."""

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:8002",
        timeout_s: float = 300.0,
        client: Optional[httpx.AsyncClient] = None,
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout_s = timeout_s
        self._client = client

    async def extract(
        self,
        document_bytes: bytes,
        filename: str = "document.pdf",
    ) -> Dict[str, Any]:
        """Send document to OCR service and return layout and page model output."""
        mime = mimetypes.guess_type(filename)[0] or "application/pdf"
        files = {"file": (filename, document_bytes, mime)}

        if self._client is not None:
            resp = await self._client.post(
                f"{self.base_url}/ocr",
                files=files,
                timeout=self.timeout_s,
            )
            resp.raise_for_status()
            return resp.json()

        async with httpx.AsyncClient(timeout=self.timeout_s) as client:
            resp = await client.post(
                f"{self.base_url}/ocr",
                files=files,
            )
            resp.raise_for_status()
            return resp.json()


def process_document_locally(
    document_bytes: bytes,
    filename: str,
    model: str,
    base_url: str,
) -> Dict[str, Any]:
    """Run PaddleOCR-VL and the organizer in-process.

    ``ocr_pipeline.process_document`` takes a filesystem path, so the uploaded
    bytes are written to a short-lived temporary file. This function is blocking
    (Paddle inference plus a synchronous Ollama request) and must be called from
    a worker thread.
    """
    from ocr_pipeline import process_document

    suffix = Path(filename).suffix.lower() or ".bin"
    with tempfile.TemporaryDirectory(prefix="careflow-ocr-") as temp_dir:
        path = Path(temp_dir) / f"document{suffix}"
        path.write_bytes(document_bytes)
        return process_document(path, model=model, base_url=base_url)


# -----------------------------------------------------------------------------
# Intake Job Registry
# -----------------------------------------------------------------------------

@dataclass
class IntakeJob:
    job_id: str
    case_id: str
    document_id: str
    kind: str  # "audio" | "document"
    filename: str
    stage: str = "queued"  # queued -> transcribing/reading -> ingesting -> processing -> complete/failed
    status: str = "queued"  # queued | running | complete | failed
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    error: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    auto_process: bool = True
    target_language: str = "en-IN"

    def update_stage(self, stage: str, status: Optional[str] = None) -> None:
        self.stage = stage
        if status:
            self.status = status
        elif stage in ("transcribing", "reading", "ingesting", "processing"):
            self.status = "running"
        elif stage == "complete":
            self.status = "complete"
        elif stage == "failed":
            self.status = "failed"
        self.updated_at = datetime.now(timezone.utc)

    def fail(self, error: str) -> None:
        self.stage = "failed"
        self.status = "failed"
        self.error = error
        self.updated_at = datetime.now(timezone.utc)

    def finish(self, result: Dict[str, Any]) -> None:
        self.stage = "complete"
        self.status = "complete"
        self.result = result
        self.updated_at = datetime.now(timezone.utc)

    @property
    def elapsed_seconds(self) -> float:
        return (datetime.now(timezone.utc) - self.created_at).total_seconds()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "job_id": self.job_id,
            "case_id": self.case_id,
            "document_id": self.document_id,
            "kind": self.kind,
            "filename": self.filename,
            "stage": self.stage,
            "status": self.status,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "elapsed_seconds": round(self.elapsed_seconds, 1),
            "error": self.error,
            "result": self.result,
            "auto_process": self.auto_process,
        }


class IntakeJobRegistry:
    """Thread-safe in-process registry for tracking asynchronous intake jobs."""

    def __init__(self):
        self._jobs: Dict[str, IntakeJob] = {}
        self._lock = threading.Lock()

    def register(self, job: IntakeJob) -> IntakeJob:
        with self._lock:
            self._jobs[job.job_id] = job
            return job

    def get(self, job_id: str) -> Optional[IntakeJob]:
        with self._lock:
            return self._jobs.get(job_id)

    def list_for_case(self, case_id: str) -> List[IntakeJob]:
        with self._lock:
            return [j for j in self._jobs.values() if j.case_id == case_id]


# -----------------------------------------------------------------------------
# Intake Service
# -----------------------------------------------------------------------------

class IntakeService:
    """Coordinates direct intake from file/audio upload to transcription/OCR,

    adaptation, persistence, and pipeline submission.
    """

    def __init__(
        self,
        settings: Settings,
        db: Database,
        cipher: Cipher,
        documents: DocumentStore,
        pipeline: PipelineService,
        stt_service: Optional[SttService] = None,
        ocr_client: Optional[OcrClient] = None,
        registry: Optional[IntakeJobRegistry] = None,
    ):
        self.settings = settings
        self.db = db
        self.cipher = cipher
        self.documents = documents
        self.pipeline = pipeline
        self.stt_service = stt_service or LocalSttService(
            timeout_s=settings.stt_timeout_s,
        )
        # An explicitly injected client keeps the historical HTTP path (used by
        # tests and by deployments that still want the standalone OCR service).
        # Without one, document intake runs ocr_pipeline in-process.
        self._ocr_client_injected = ocr_client is not None
        self.ocr_client = ocr_client or OcrClient(
            base_url=settings.ocr_base_url,
            timeout_s=settings.ocr_timeout_s,
        )
        self.registry = registry or IntakeJobRegistry()

    def create_job(
        self,
        case_id: str,
        document_id: str,
        kind: str,
        filename: str,
        auto_process: bool = True,
        target_language: str = "en-IN",
    ) -> IntakeJob:
        job = IntakeJob(
            job_id=random_id("intake"),
            case_id=case_id,
            document_id=document_id,
            kind=kind,
            filename=filename,
            auto_process=auto_process,
            target_language=target_language,
        )
        return self.registry.register(job)

    def get_job(self, job_id: str) -> Optional[IntakeJob]:
        return self.registry.get(job_id)

    async def process_audio_job(
        self,
        job_id: str,
        audio_bytes: bytes,
        user_id: str,
        role: str,
    ) -> None:
        """Run STT for an intake job, adapt the transcript, and persist sources."""
        job = self.registry.get(job_id)
        if job is None:
            logger.error("Intake job %s not found in registry", job_id)
            return

        try:
            job.update_stage("transcribing")

            # Run the in-repo Sarvam implementation directly (no HTTP hop).
            stt_result = await self.stt_service.transcribe(
                audio_bytes=audio_bytes,
                filename=job.filename,
                target_language=job.target_language,
            )

            # Re-check case deletion / consent before persistence so withdrawn
            # cases cannot be repopulated.
            case = self.db.get_case(job.case_id, include_deleted=True)
            if case is None or case.deleted:
                job.fail("Case was deleted during intake.")
                logger.warning("Case %s deleted before STT persistence; aborted.", job.case_id)
                return
            if not case.consent_granted:
                job.fail("Consent was withdrawn during intake.")
                logger.warning("Consent withdrawn for case %s before STT persistence; aborted.", job.case_id)
                return

            # Adapt result, passing document_id so audio evidence can be played back
            stt_result["document_id"] = job.document_id
            stt_result["file_name"] = job.filename
            sources, notes = adapt_stt(stt_result, job.case_id)

            job.update_stage("ingesting")
            ingest_res = persist_sources(
                db=self.db,
                cipher=self.cipher,
                case=case,
                sources=sources,
                notes=notes,
                user_id=user_id,
                role=role,
                kind="audio_stt",
            )

            # Optional pipeline submission
            if job.auto_process:
                job.update_stage("processing")
                if self.settings.processing_mode == "sync":
                    self.pipeline.process_case(job.case_id, actor=user_id)
                else:
                    self.pipeline.submit(job.case_id, actor=user_id)

            job.finish({
                "document_id": job.document_id,
                "inserted": len(ingest_res["inserted"]),
                "duplicates": len(ingest_res["duplicates"]),
                "notes": notes,
                "sources": ingest_res["sources"],
            })
            logger.info("Audio intake job %s completed successfully", job_id)

        except Exception as exc:
            safe_msg = f"Audio transcription failed: {safe_intake_error(exc)}"
            stage = getattr(exc, "stage", "integration")
            logger.exception(
                "Audio intake job %s failed during %s: %s", job_id, stage, safe_msg
            )
            # The original document remains in DocumentStore and DB for retry/inspection
            job.fail(safe_msg)

    async def process_document_job(
        self,
        job_id: str,
        document_bytes: bytes,
        user_id: str,
        role: str,
    ) -> None:
        """Run OCR for an intake job, adapt the document layout, and persist sources."""
        job = self.registry.get(job_id)
        if job is None:
            logger.error("Intake job %s not found in registry", job_id)
            return

        try:
            job.update_stage("reading")

            if self._ocr_client_injected:
                # Backward-compatible path for tests and external deployments.
                ocr_result = await self.ocr_client.extract(
                    document_bytes=document_bytes,
                    filename=job.filename,
                )
            else:
                # Run PaddleOCR-VL + organizer in-process. Both are blocking,
                # so keep them off the event loop.
                ollama_url = self.settings.ollama_base_url.rstrip("/")
                if not ollama_url.endswith("/api/chat"):
                    ollama_url = f"{ollama_url}/api/chat"
                ocr_result = await run_in_threadpool(
                    process_document_locally,
                    document_bytes,
                    job.filename,
                    self.settings.ollama_model,
                    ollama_url,
                )

            # Re-check case deletion / consent before persistence so withdrawn
            # cases cannot be repopulated.
            case = self.db.get_case(job.case_id, include_deleted=True)
            if case is None or case.deleted:
                job.fail("Case was deleted during intake.")
                logger.warning("Case %s deleted before OCR persistence; aborted.", job.case_id)
                return
            if not case.consent_granted:
                job.fail("Consent was withdrawn during intake.")
                logger.warning("Consent withdrawn for case %s before OCR persistence; aborted.", job.case_id)
                return

            # Override the service's temporary file_name with the original filename
            # and pass the internal document_id; preserve page/bbox metadata.
            ocr_result["file_name"] = job.filename
            ocr_result["document_id"] = job.document_id
            sources, notes = adapt_ocr(ocr_result, job.case_id)

            job.update_stage("ingesting")
            ingest_res = persist_sources(
                db=self.db,
                cipher=self.cipher,
                case=case,
                sources=sources,
                notes=notes,
                user_id=user_id,
                role=role,
                kind="document_ocr",
            )

            # Optional pipeline submission
            if job.auto_process:
                job.update_stage("processing")
                if self.settings.processing_mode == "sync":
                    self.pipeline.process_case(job.case_id, actor=user_id)
                else:
                    self.pipeline.submit(job.case_id, actor=user_id)

            job.finish({
                "document_id": job.document_id,
                "inserted": len(ingest_res["inserted"]),
                "duplicates": len(ingest_res["duplicates"]),
                "notes": notes,
                "sources": ingest_res["sources"],
            })
            logger.info("Document intake job %s completed successfully", job_id)

        except Exception as exc:
            safe_msg = f"Document OCR extraction failed: {safe_intake_error(exc)}"
            logger.exception("Document intake job %s failed: %s", job_id, safe_msg)
            # The original document remains in DocumentStore and DB for retry/inspection
            job.fail(safe_msg)
