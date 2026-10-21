"""Direct audio and document intake services for CareFlow AI.

Provides async clients for STT and OCR services, an in-process intake job registry,
and lifecycle handling from upload to background extraction, persistence, and pipeline submission.
"""
from __future__ import annotations

import logging
import mimetypes
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

import httpx

from .config import Settings
from .db import Database
from .pipeline.normalize import InputError, adapt_ocr, adapt_stt
from .pipeline.orchestrator import PipelineService
from .schemas import CaseRecord, CaseStatus, SourceRecord
from .security import Principal
from .storage import Cipher, DocumentStore, random_id, safe_error

logger = logging.getLogger("careflow.intake")


def safe_intake_error(exc: Exception) -> str:
    """Return a safe, retryable error message for intake failures."""
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
# HTTP Clients for STT and OCR Services
# -----------------------------------------------------------------------------

class SttClient:
    """Async client for the CareFlow STT & Speech Translation service."""

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:8001",
        timeout_s: float = 120.0,
        client: Optional[httpx.AsyncClient] = None,
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout_s = timeout_s
        self._client = client

    async def transcribe(
        self,
        audio_bytes: bytes,
        filename: str = "audio.wav",
        target_language: str = "en-IN",
    ) -> Dict[str, Any]:
        """Send audio to STT service and return structured chunk and transcription results."""
        mime = mimetypes.guess_type(filename)[0] or "audio/wav"
        files = {"audio": (filename, audio_bytes, mime)}
        data = {"target_language": target_language}

        if self._client is not None:
            resp = await self._client.post(
                f"{self.base_url}/speech-to-language",
                files=files,
                data=data,
                timeout=self.timeout_s,
            )
            resp.raise_for_status()
            return resp.json()

        async with httpx.AsyncClient(timeout=self.timeout_s) as client:
            resp = await client.post(
                f"{self.base_url}/speech-to-language",
                files=files,
                data=data,
            )
            resp.raise_for_status()
            return resp.json()


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
        stt_client: Optional[SttClient] = None,
        ocr_client: Optional[OcrClient] = None,
        registry: Optional[IntakeJobRegistry] = None,
    ):
        self.settings = settings
        self.db = db
        self.cipher = cipher
        self.documents = documents
        self.pipeline = pipeline
        self.stt_client = stt_client or SttClient(
            base_url=settings.stt_base_url,
            timeout_s=settings.stt_timeout_s,
        )
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

            # Call STT service
            stt_result = await self.stt_client.transcribe(
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
            logger.exception("Audio intake job %s failed: %s", job_id, safe_msg)
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

            # Call OCR service
            ocr_result = await self.ocr_client.extract(
                document_bytes=document_bytes,
                filename=job.filename,
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
