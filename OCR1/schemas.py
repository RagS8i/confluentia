from typing import Any

from pydantic import BaseModel, Field

# Extensions accepted by PaddleOCR-VL through the OCR service.
SUPPORTED_EXTENSIONS = frozenset(
    {
        ".pdf",
        ".png",
        ".jpg",
        ".jpeg",
        ".webp",
        ".bmp",
        ".tif",
        ".tiff",
    }
)


class OcrPage(BaseModel):
    """One page of PaddleOCR-VL output."""

    page_number: int = Field(ge=1)
    model_output: dict[str, Any]


class OcrDocument(BaseModel):
    """Strict output contract for the OCR worker."""

    file_name: str = Field(min_length=1)
    page_count: int = Field(ge=0)
    pages: list[OcrPage]
