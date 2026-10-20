from contextlib import asynccontextmanager
import logging
import tempfile
from pathlib import Path
from threading import Lock

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool

try:  # Imported as the OCR1 package.
    from .schemas import SUPPORTED_EXTENSIONS
except ImportError:  # Run with --app-dir OCR1.
    from schemas import SUPPORTED_EXTENSIONS  # type: ignore[no-redef]

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# PaddleOCR's cached pipeline is shared across requests; serialize inference
# so concurrent uploads don't run the model at the same time.
model_lock = Lock()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # The OCR pipeline is created lazily on the first request.
    yield


app = FastAPI(
    title="Careflow OCR API",
    lifespan=lifespan,
)


@app.get("/health")
async def health():
    return {"status": "ok"}


def _extract(path: Path) -> dict:
    with model_lock:
        try:
            from .model import extract_document
        except ImportError:
            from model import extract_document  # type: ignore[no-redef]
        return extract_document(path)


@app.post("/ocr")
async def ocr(file: UploadFile = File(...)):
    filename = file.filename or "upload"
    suffix = Path(filename).suffix.lower()

    if suffix not in SUPPORTED_EXTENSIONS:
        supported = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise HTTPException(
            status_code=415,
            detail=(
                f"Unsupported file type: {suffix or '<none>'}. "
                f"Supported types: {supported}"
            ),
        )

    data = await file.read()
    if not data:
        raise HTTPException(
            status_code=400,
            detail="The uploaded file is empty.",
        )

    try:
        with tempfile.TemporaryDirectory(prefix="ocr-") as temp_dir:
            path = Path(temp_dir) / f"upload{suffix}"
            path.write_bytes(data)

            # PaddleOCR is blocking and CPU/GPU heavy, so keep it off the
            # event loop.
            return await run_in_threadpool(_extract, path)

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("OCR extraction failed")
        raise HTTPException(
            status_code=500,
            detail="OCR extraction failed.",
        ) from exc
