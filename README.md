# budget-ai-vllm
A lightweight, self-hosted LLM endpoint designed to run with high concurrency. Powered by vLLM and exposed via a simple FastAPI REST API.

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

- Starts a `vLLM` server with **Qwen2.5-Coder 7B Instruct** by default using **Podman**.
- vLLM provides high throughput and efficient GPU utilization with PagedAttention.
- Supports high concurrency across multiple users.
- Starts a FastAPI wrapper that forwards prompts to vLLM's OpenAI-compatible API.

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
- `VLLM_PORT` = `8080`
- `VLLM_SERVER_URL` = `http://127.0.0.1:8080`
- `VLLM_SERVER_TIMEOUT` = `120`
- `VLLM_IMAGE` = `vllm/vllm-openai:latest`
- `MODEL_NAME` = `Qwen/Qwen2.5-Coder-7B-Instruct` (Hugging Face model ID)
- `HF_HOME` = `./hf_cache` (cache directory for downloaded models)
