from functools import lru_cache
from pathlib import Path
from typing import Any

try:  # Imported as the OCR1 package.
    from .schemas import SUPPORTED_EXTENSIONS, OcrDocument, OcrPage
except ImportError:  # Run with --app-dir OCR1.
    from schemas import (  # type: ignore[no-redef]
        SUPPORTED_EXTENSIONS,
        OcrDocument,
        OcrPage,
    )

# Re-exported for callers that imported this constant from `model`.
__all__ = ["SUPPORTED_EXTENSIONS", "extract_document", "get_ocr_pipeline"]


@lru_cache(maxsize=1)
def get_ocr_pipeline() -> Any:
    """Initialize the OCR model once and reuse it."""
    # Paddle and PyTorch both ship a Windows ``shm.dll``. Importing Paddle
    # first makes the later modelscope -> torch import fail with WinError 127.
    # Preloading torch keeps both inference stacks loadable in one process.
    try:
        import torch  # noqa: F401
    except Exception:
        pass
    try:
        from paddleocr import PaddleOCRVL
    except ImportError as exc:
        raise RuntimeError(
            "paddleocr is required for OCR inference. Install with `pip install -r OCR1/requirements.txt`."
        ) from exc
    return PaddleOCRVL()


def make_json_serializable(value: Any) -> Any:
    """Convert NumPy/Paddle objects and nested values to JSON-safe values."""

    if isinstance(value, dict):
        return {
            str(key): make_json_serializable(item)
            for key, item in value.items()
        }

    if isinstance(value, (list, tuple)):
        return [make_json_serializable(item) for item in value]

    # PaddleX result blocks expose `to_dict()`; without this the block content
    # would be stringified into an opaque repr instead of usable text.
    to_dict = getattr(value, "to_dict", None)
    if callable(to_dict):
        return make_json_serializable(to_dict())

    if hasattr(value, "tolist"):
        return make_json_serializable(value.tolist())

    if hasattr(value, "item"):
        return make_json_serializable(value.item())

    if value is None or isinstance(value, (str, int, float, bool)):
        return value

    return str(value)


def _page_output(result: Any) -> dict[str, Any]:
    """Normalize one PaddleOCR result into a dictionary.

    PaddleX exposes a string-oriented view (`.str`) that expands layout blocks
    into plain dictionaries. Fall back to `.json` for other result versions.
    """

    raw = getattr(result, "str", None)
    if raw is None:
        raw = getattr(result, "json", None)
    if raw is None:
        raw = result

    data = make_json_serializable(raw)
    return data if isinstance(data, dict) else {"value": data}


def extract_document(file_path: str | Path) -> dict[str, Any]:
    """
    Extract structured content from an image or PDF using PaddleOCR-VL.

    Args:
        file_path: Path to a local image or PDF.

    Returns:
        A dictionary containing the model's structured output for each page.
    """
    path = Path(file_path).expanduser().resolve()

    if not path.is_file():
        raise FileNotFoundError(f"File not found: {path}")

    if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise ValueError(
            f"Unsupported file type: {path.suffix}. "
            "Provide an image or PDF."
        )

    pipeline = get_ocr_pipeline()

    # A PDF produces separate prediction results for its pages.
    results = list(pipeline.predict(input=str(path)))

    # Strict output contract.
    return OcrDocument(
        file_name=path.name,
        page_count=len(results),
        pages=[
            OcrPage(page_number=page_number, model_output=_page_output(result))
            for page_number, result in enumerate(results, start=1)
        ],
    ).model_dump()
