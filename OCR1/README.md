# Careflow OCR service

FastAPI wrapper around the PaddleOCR-VL pipeline in `model.py`.

The orchestrator calls `POST /ocr` over HTTP. The service is also independently
callable. See the root `README.md` for the complete Careflow architecture.

## Install

```sh
pip install -r OCR1/requirements.txt
```

On Linux with an NVIDIA GPU, replace `paddlepaddle` with the matching
`paddlepaddle-gpu` build for your CUDA version. PaddleOCR-VL weights are
downloaded to `PADDLE_PDX_CACHE_HOME` (default `~/.paddlex/official_models`) on
first use.

## Run

From the repository root:

```sh
uvicorn OCR1.api:app --host 127.0.0.1 --port 8002 --reload
```

Or from inside the folder:

```sh
cd OCR1
uvicorn api:app --port 8002 --reload
```

## Endpoints

### `GET /health`

```json
{"status": "ok"}
```

### `POST /ocr`

Multipart upload with a single `file` field. Supported extensions:

```
.pdf .png .jpg .jpeg .webp .bmp .tif .tiff
```

```sh
curl -X POST http://127.0.0.1:8002/ocr \
  -F "file=@scan.pdf"
```

Response:

```json
{
  "file_name": "upload.pdf",
  "page_count": 1,
  "pages": [
    {
      "page_number": 1,
      "model_output": {
        "res": {
          "parsing_res_list": [
            {
              "block_label": "text",
              "block_content": "Hemoglobin: 12.5 g/dL",
              "block_order": 1
            }
          ]
        }
      }
    }
  ]
}
```

PaddleX layout blocks are normalized with `to_dict()` so `block_content` is
real text rather than an object repr. The orchestrator's `ocr_text.py` extracts
those blocks in reading order and falls back to `overall_ocr_res.rec_texts`.

Errors:

| Status | Meaning |
| --- | --- |
| 400 | The uploaded file is empty |
| 415 | Extension is not in `SUPPORTED_EXTENSIONS` |
| 500 | OCR extraction failed (details are logged server-side) |
