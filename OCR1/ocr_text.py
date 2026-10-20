"""Convert the OCR service's structured response into plain text.

The OCR service returns the PaddleOCR-VL result per page.  PaddleX exposes
layout blocks under `parsing_res_list` with `block_label` and `block_content`,
and a line-level fallback under `overall_ocr_res.rec_texts`.  This module
extracts text in reading order and ignores non-textual blocks.
"""

from typing import Any, Iterable

from OCR1.schemas import OcrDocument

# Layout labels that carry no usable clinical text.
_SKIP_LABELS = frozenset({"image", "header_image", "footer_image", "seal"})

# Keys that hold textual content, in descending order of preference.
_TEXT_KEYS = (
    "block_content",
    "rec_text",
    "text",
    "markdown",
    "content",
)


class OcrTextError(ValueError):
    """The OCR response did not contain usable text."""


def _blocks(value: Any) -> list[dict[str, Any]]:
    """Return every `parsing_res_list` found anywhere in the payload."""

    found: list[dict[str, Any]] = []

    if isinstance(value, dict):
        for key, item in value.items():
            if key == "parsing_res_list" and isinstance(item, list):
                found.extend(block for block in item if isinstance(block, dict))
            else:
                found.extend(_blocks(item))
    elif isinstance(value, list):
        for item in value:
            found.extend(_blocks(item))

    return found


def _block_order(block: dict[str, Any]) -> tuple[int, int]:
    raw = block.get("block_order", block.get("block_id"))
    return (0, raw) if isinstance(raw, int) else (1, 0)


def _text_from_block(block: dict[str, Any]) -> str | None:
    if block.get("block_label") in _SKIP_LABELS:
        return None

    for key in _TEXT_KEYS:
        value = block.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()

    return None


def _strings_for_key(value: Any, key: str) -> list[str]:
    """Collect non-empty strings under `key` from a nested payload."""

    found: list[str] = []

    if isinstance(value, dict):
        for item_key, item in value.items():
            if item_key == key:
                found.extend(_as_strings(item))
            else:
                found.extend(_strings_for_key(item, key))
    elif isinstance(value, list):
        for item in value:
            found.extend(_strings_for_key(item, key))

    return found


def _as_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, Iterable) and not isinstance(value, (dict, bytes)):
        return [
            item.strip()
            for item in value
            if isinstance(item, str) and item.strip()
        ]
    return []


def _page_text(model_output: dict[str, Any]) -> list[str]:
    blocks = _blocks(model_output)

    if blocks:
        ordered = sorted(blocks, key=_block_order)
        texts = [
            text
            for block in ordered
            if (text := _text_from_block(block)) is not None
        ]
        if texts:
            return texts

        # A page with only images/seals is still valid, but it has no text.
        # Do not re-scan block_content here: that would resurrect skipped
        # non-textual blocks.
        return _strings_for_key(model_output, "rec_texts")

    # No layout blocks: use line-level OCR text, then generic textual keys.
    for key in ("rec_texts",):
        texts = _strings_for_key(model_output, key)
        if texts:
            return texts

    texts: list[str] = []
    for key in _TEXT_KEYS:
        texts.extend(_strings_for_key(model_output, key))

    return texts


def ocr_document_to_text(document: OcrDocument | dict[str, Any]) -> str:
    """Return the document's text in page and reading order."""

    try:
        parsed = (
            document
            if isinstance(document, OcrDocument)
            else OcrDocument.model_validate(document)
        )
    except Exception as exc:  # noqa: BLE001 - surfaced as an OCR stage failure
        raise OcrTextError("OCR response did not match the expected format.") from exc

    pages: list[str] = []

    for page in parsed.pages:
        lines = _page_text(page.model_output)

        # Drop adjacent duplicates that PaddleOCR sometimes emits per block.
        deduped = [
            line
            for index, line in enumerate(lines)
            if index == 0 or line != lines[index - 1]
        ]
        if deduped:
            pages.append("\n".join(deduped))

    text = "\n\n".join(pages).strip()

    if not text:
        raise OcrTextError("OCR returned no usable text.")

    return text
