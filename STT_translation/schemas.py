from enum import Enum

from pydantic import BaseModel, Field


class Language(str, Enum):
    """
    Supported target languages, using Sarvam BCP-47 codes.

    Only English is currently supported because saaras runs in "translate"
    mode, which always returns English. Add codes here only when the
    translation path can actually produce that language.
    """

    ENGLISH = "en-IN"


class SpeechTranslationRequest(BaseModel):
    target_language: Language = Field(
        default=Language.ENGLISH,
        description="Language to translate the audio into",
    )


class SpeechTranslationInput(BaseModel):
    """Strict input contract for the STT worker."""

    filename: str = Field(min_length=1)
    target_language: Language = Language.ENGLISH


class TranscriptChunk(BaseModel):
    """One silence-aware chunk of the transcription/translation result."""

    index: int = Field(ge=0)
    start_seconds: float = Field(ge=0)
    end_seconds: float = Field(ge=0)
    translated_text: str
    language_code: str | None = None
    language_probability: float | None = Field(default=None, ge=0, le=1)
    request_id: str | None = None


class SpeechTranslationResult(BaseModel):
    """Strict output contract for the STT worker."""

    translated_text: str
    target_language: str
    chunks: list[TranscriptChunk]
