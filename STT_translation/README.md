# Careflow STT service

FastAPI wrapper around Sarvam speech-to-text and translation (`stt.py`).

The orchestrator calls `POST /speech-to-language` over HTTP. The service is also
independently callable. See the root `README.md` for the complete architecture.

## Install

```sh
pip install -r STT_translation/requirements.txt
sudo apt-get install ffmpeg   # macOS: brew install ffmpeg
```

Set `SARVAM_API_KEY` in the repository `.env` or the process environment.
`SARVAM_TRANSLATE_MODEL` defaults to `sarvam-translate:v1`.

## Run

From the repository root:

```sh
uvicorn STT_translation.api:app --host 127.0.0.1 --port 8001 --reload
```

Or from inside the folder:

```sh
cd STT_translation
uvicorn api:app --port 8001 --reload
```

## Endpoints

### `GET /health`

```json
{"status": "ok"}
```

### `POST /speech-to-language`

Multipart fields:

- `audio` (file, required)
- `target_language` (`en-IN`, default)

```sh
curl -X POST http://127.0.0.1:8001/speech-to-language \
  -F "audio=@synthetic_visit.wav" \
  -F "target_language=en-IN"
```

Response:

```json
{
  "transcription": "Original-language transcript",
  "translated_text": "English translation",
  "target_language": "en-IN",
  "chunks": [
    {
      "index": 0,
      "start_seconds": 0.0,
      "end_seconds": 6.5,
      "transcription": "...",
      "translated_text": "...",
      "language_code": "en-IN",
      "language_probability": 0.95,
      "speech_to_text_request_id": "...",
      "translation_request_id": null
    }
  ]
}
```

Audio is split at silence into chunks of at most 28 seconds (target ~26 s)
because Sarvam's REST endpoint rejects longer audio. The orchestrator uses
`translated_text`, falling back to `transcription` when translation is empty.
Audio content is sent to the configured Sarvam cloud API.
