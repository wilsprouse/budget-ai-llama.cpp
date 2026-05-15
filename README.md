# budget-ai-llama.cpp
A lightweight, self-hosted LLM endpoint designed to run on cheap/minimal hardware. Powered by llama.cpp and exposed via a simple FastAPI REST API.

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

- Starts a `llama.cpp` server with **TinyLlama** by default using **Podman**.
- Uses low-resource defaults for minimal hardware (`Q4_K_M`, `ctx=512`, `threads=1`, `ngl=0`).
- Starts a FastAPI wrapper that forwards prompts to llama.cpp.

## API usage

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Generate text (response streams as SSE):

```bash
curl -N -X POST http://127.0.0.1:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Write one sentence about tiny models.","max_tokens":64,"temperature":0.7}'
```

Each token arrives as an SSE line, e.g. `data: {"content":"Hello"}`.

## Configuration

Environment variables:

- `FASTAPI_HOST` (default `0.0.0.0`)
- `FASTAPI_PORT` (default `8000`)
- `LLAMA_PORT` (default `8080`)
- `MODEL_DIR` (default `./models`)
- `MODEL_NAME` (default `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf`)
- `MODEL_URL` (default TinyLlama GGUF from Hugging Face)
