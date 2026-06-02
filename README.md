# budget-ai-llama.cpp
A lightweight, self-hosted LLM endpoint using llama.cpp with GGUF quantized models. Exposed via a simple FastAPI REST API.

## Quick start

```bash
./start.sh --install-deps
```

Start services normally:

```bash
./start.sh
```

Start services in detached mode:

```bash
./start.sh -d
```

## What `start.sh` does

- On first run, downloads the **Codestral 22B (Q4_K_M quantized GGUF)** model from Hugging Face using huggingface-hub.
- Starts a `llama.cpp` server with the GGUF model using **Podman** with GPU acceleration.
- llama.cpp provides efficient inference with quantized GGUF models for reduced memory usage.
- Starts a FastAPI wrapper that forwards chat requests to llama.cpp's completion API.

## API usage

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Generate text (response streams as SSE):

```bash
curl -N -X POST http://127.0.0.1:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Write one sentence about tiny models."}],"max_tokens":64,"temperature":0.7}'
```

Each token arrives as an SSE line, e.g. `data: {"content":"Hello"}`.

## Configuration

All configuration is managed through environment variables. Before running the application:

1. Copy `.env.template` to `.env`:
   ```bash
   cp .env.template .env
   ```

2. (Optional) Customize values in `.env` to suit your needs.

Default environment variables (as defined in `.env.template`):

- `FASTAPI_HOST` = `0.0.0.0`
- `FASTAPI_PORT` = `8000`
- `LLAMA_PORT` = `8080`
- `LLAMA_SERVER_URL` = `http://127.0.0.1:8080`
- `LLAMA_SERVER_TIMEOUT` = `120`
- `LLAMA_IMAGE` = `ghcr.io/ggml-org/llama.cpp:server-cuda`
- `MODEL_NAME` = `bartowski/Codestral-22B-v0.1-GGUF` (Hugging Face model ID)
- `MODEL_FILE` = `Codestral-22B-v0.1-Q4_K_M.gguf` (specific GGUF file to download)
- `MODEL_DIR` = `./models` (directory for downloaded models)
