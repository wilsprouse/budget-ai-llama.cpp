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

- Starts a `llama.cpp` server with **Qwen2.5-Coder 7B** by default using **Podman**.
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
- `LLAMA_IMAGE` = `ghcr.io/ggml-org/llama.cpp:server`
- `MODEL_DIR` = `./models`
- `MODEL_NAME` = `qwen2.5-coder-7b-instruct-q4_k_m.gguf`
- `MODEL_URL` = `https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf`
