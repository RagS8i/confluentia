"""Failure types raised by the in-repo speech-to-language pipeline.

Kept dependency-free so callers (CareFlow intake, the standalone API, tests)
can classify failures without importing the Sarvam SDK or audio libraries.
"""


class SpeechTranslationError(RuntimeError):
    """Base class for speech transcription/translation failures."""

    stage = "speech_to_language"


class AudioDecodeError(SpeechTranslationError):
    """The uploaded bytes could not be decoded as audio."""

    stage = "audio_decode"


class TranscriptionError(SpeechTranslationError):
    """Sarvam speech-to-text failed for a chunk."""

    stage = "transcription"


class TranslationError(SpeechTranslationError):
    """Sarvam translation failed for a transcribed chunk."""

    stage = "translation"
