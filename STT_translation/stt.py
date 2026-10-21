import math
import os
import tempfile
from pathlib import Path

from dotenv import load_dotenv
from pydub import AudioSegment
from pydub.silence import detect_nonsilent
from sarvamai import SarvamAI

_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"

if _ENV_PATH.is_file():
    load_dotenv(_ENV_PATH)
else:
    load_dotenv()

_client = None


def get_sarvam_client() -> SarvamAI:
    global _client
    if _client is not None:
        return _client
    api_key = os.getenv("SARVAM_API_KEY")
    if not api_key:
        raise RuntimeError("SARVAM_API_KEY missing from environment or .env")
    _client = SarvamAI(api_subscription_key=api_key)
    return _client

# Sarvam's REST speech-to-text endpoint accepts audio under 30 seconds.
# Aim for ~26 s chunks so cuts land on silence well before that limit.
CHUNK_TARGET_MS = 26_000
CHUNK_MAX_MS = 28_000
MIN_SILENCE_MS = 300
SILENCE_THRESHOLD_DB = 16

STT_MODEL = "saaras:v4"
STT_LANGUAGE = "unknown"  # Auto-detect the spoken language.

# sarvam-translate:v1 covers every language exposed in schemas.Language.
# Switch to "mayura:v1" if you only need the 11 core languages and want its
# extra modes, but note it rejects the newer codes (as-IN, brx-IN, ...).
TRANSLATE_MODEL = os.getenv("SARVAM_TRANSLATE_MODEL", "sarvam-translate:v1")


def _speech_ranges(audio: AudioSegment) -> list[tuple[int, int]]:
    """Return non-silent (start_ms, end_ms) ranges in the audio."""

    duration_ms = len(audio)
    if duration_ms == 0:
        return []

    # dBFS is -inf for completely silent audio, which is not a usable
    # threshold for detect_nonsilent.
    if not math.isfinite(audio.dBFS):
        return [(0, duration_ms)]

    ranges = detect_nonsilent(
        audio,
        min_silence_len=MIN_SILENCE_MS,
        silence_thresh=audio.dBFS - SILENCE_THRESHOLD_DB,
    )
    return ranges or [(0, duration_ms)]


def _bounded_ranges(
    ranges: list[tuple[int, int]],
    duration_ms: int,
) -> list[tuple[int, int]]:
    """Clamp ranges and hard-split any continuous speech longer than the limit."""

    bounded: list[tuple[int, int]] = []

    for start, end in ranges:
        start = max(0, min(start, duration_ms))
        end = max(start, min(end, duration_ms))

        while end - start > CHUNK_MAX_MS:
            bounded.append((start, start + CHUNK_MAX_MS))
            start += CHUNK_MAX_MS

        if end > start:
            bounded.append((start, end))

    return bounded


def _split_on_silence(audio: AudioSegment) -> list[tuple[int, int, AudioSegment]]:
    """
    Split audio into chunks of at most CHUNK_MAX_MS.

    Chunks are cut at natural pauses near CHUNK_TARGET_MS. Only continuous
    speech longer than CHUNK_MAX_MS is split at a hard boundary, since the
    Sarvam REST endpoint cannot accept anything longer.

    Returns (start_ms, end_ms, segment) tuples.
    """

    duration_ms = len(audio)
    if duration_ms <= CHUNK_MAX_MS:
        return [(0, duration_ms, audio)]

    ranges = _bounded_ranges(_speech_ranges(audio), duration_ms)
    if not ranges:
        return [(0, duration_ms, audio)]

    groups: list[tuple[int, int]] = []
    group_start, group_end = ranges[0]

    for start, end in ranges[1:]:
        fits_limit = end - group_start <= CHUNK_MAX_MS
        needs_more_audio = group_end - group_start < CHUNK_TARGET_MS

        if fits_limit and needs_more_audio:
            group_end = end
            continue

        groups.append((group_start, group_end))
        group_start, group_end = start, end

    groups.append((group_start, group_end))

    return [
        (start, end, audio[start:end])
        for start, end in groups
        if end > start
    ]


def _export_chunk(chunk: AudioSegment, path: Path) -> None:
    """Export a chunk as 16 kHz mono 16-bit PCM WAV."""

    chunk = (
        chunk.set_frame_rate(16_000)
        .set_channels(1)
        .set_sample_width(2)
    )
    chunk.export(path, format="wav")


def speech_to_language(
    audio_bytes: bytes,
    target_language: str,
    filename: str = "audio.wav",
) -> dict:
    """
    Transcribe an audio file and translate it into the target language.

    Args:
        audio_bytes: Raw contents of the uploaded audio file.
        target_language: Sarvam BCP-47 target code, e.g. "hi-IN".
        filename: Original filename, used only to infer the input format.

    Returns:
        A dict with the full transcription, full translated text, target
        language, and per-chunk Sarvam outputs (detected language, language
        probability, request IDs, and timings).
    """

    if not audio_bytes:
        raise ValueError("Audio file is empty.")

    suffix = Path(filename).suffix or ".wav"

    with tempfile.TemporaryDirectory(prefix="speech-translation-") as temp_dir:
        temp_path = Path(temp_dir)
        input_path = temp_path / f"input{suffix}"
        input_path.write_bytes(audio_bytes)

        audio = AudioSegment.from_file(input_path)
        chunk_results = []
        transcriptions = []
        translations = []

        for index, (start_ms, end_ms, segment) in enumerate(
            _split_on_silence(audio)
        ):
            chunk_path = temp_path / f"chunk_{index:04d}.wav"
            _export_chunk(segment, chunk_path)

            # Step 1: speech -> original-language text, with autodetection.
            with chunk_path.open("rb") as audio_file:
                stt_response = get_sarvam_client().speech_to_text.transcribe(
                    file=audio_file,
                    model=STT_MODEL,
                    mode="codemix",
                    language_code=STT_LANGUAGE,
                )

            transcript = (stt_response.transcript or "").strip()
            detected_language = stt_response.language_code

            # Step 2: original-language text -> target language.
            translated_text = ""
            translation_request_id = None

            if transcript:
                if detected_language == target_language:
                    translated_text = transcript
                else:
                    translation_response = get_sarvam_client().text.translate(
                        input=transcript,
                        source_language_code=detected_language or "auto",
                        target_language_code=target_language,
                        model=TRANSLATE_MODEL,
                    )
                    translated_text = (
                        translation_response.translated_text or ""
                    ).strip()
                    translation_request_id = translation_response.request_id

            chunk_results.append(
                {
                    "index": index,
                    "start_seconds": round(start_ms / 1000, 2),
                    "end_seconds": round(end_ms / 1000, 2),
                    "transcription": transcript,
                    "translated_text": translated_text,
                    "language_code": detected_language,
                    "language_probability": stt_response.language_probability,
                    "speech_to_text_request_id": stt_response.request_id,
                    "translation_request_id": translation_request_id,
                }
            )

            if transcript:
                transcriptions.append(transcript)
            if translated_text:
                translations.append(translated_text)

        return {
            "transcription": " ".join(transcriptions),
            "translated_text": " ".join(translations),
            "target_language": target_language,
            "chunks": chunk_results,
        }
