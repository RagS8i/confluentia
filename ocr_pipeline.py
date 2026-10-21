
import json
import threading
from pathlib import Path
from typing import Any

from OCR1.model import extract_document
from OCR1.organizer import organize_ocr_result


# PaddleOCR's cached pipeline is shared process-wide. The HTTP service
# serialized inference with a lock; local intake calls need the same guard.
_PADDLE_LOCK = threading.Lock()


def process_document(
    file_path: str | Path,
    model: str = "qwen3:8b",
    base_url: str | None = None,
) -> dict[str, Any]:
    """
    Extract text from a document using PaddleOCR-VL,
    then organize the extracted information using Ollama.

    Args:
        file_path: Path to an image or PDF.
        model: Installed Ollama model to use.
        base_url: Optional Ollama chat endpoint. Uses the organizer default
            when omitted.

    Returns:
        OCR pages/blocks data as a Python dictionary.
    """
    path = Path(file_path).expanduser().resolve()

    if not path.is_file():
        raise FileNotFoundError(f"Document not found: {path}")

    # Step 1: Extract text using PaddleOCR-VL
    with _PADDLE_LOCK:
        ocr_output = extract_document(path)

    # Step 2: Organize the extracted text using Ollama
    if base_url:
        organized_output = organize_ocr_result(
            ocr_output,
            model=model,
            base_url=base_url,
        )
    else:
        organized_output = organize_ocr_result(
            ocr_output,
            model=model,
        )

    # Step 3: Return the structured data
    return organized_output


if __name__ == "__main__":
    result = process_document("OCR1/screenshot.png")

    print(json.dumps(
        result,
        indent=2,
        ensure_ascii=False,
    ))
