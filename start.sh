#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables from .env file if it exists
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

DETACHED=false
INSTALL_DEPS=false

# Environment variables (no defaults - must be set in .env or externally)
FASTAPI_HOST="${FASTAPI_HOST:?FASTAPI_HOST must be set. Copy .env.template to .env and configure it.}"
FASTAPI_PORT="${FASTAPI_PORT:?FASTAPI_PORT must be set. Copy .env.template to .env and configure it.}"
VLLM_PORT="${VLLM_PORT:?VLLM_PORT must be set. Copy .env.template to .env and configure it.}"

VLLM_IMAGE="${VLLM_IMAGE:?VLLM_IMAGE must be set. Copy .env.template to .env and configure it.}"
MODEL_NAME="${MODEL_NAME:?MODEL_NAME must be set. Copy .env.template to .env and configure it.}"
HF_HOME="${HF_HOME:-./hf_cache}"

usage() {
  cat <<'USAGE'
Usage: ./start.sh [--install-deps] [-d]

Options:
  --install-deps   Install required system and Python dependencies
  -d, --detached  Start FastAPI in detached mode
  -h, --help      Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-deps)
      INSTALL_DEPS=true
      shift
      ;;
    -d|--detached)
      DETACHED=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

install_deps() {
  echo "Installing dependencies..."

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y podman python3 python3-pip curl
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y podman python3 python3-pip curl
  elif command -v brew >/dev/null 2>&1; then
    brew install podman python curl
  else
    echo "Unsupported package manager. Install podman, python3, pip, and curl manually."
  fi

  python3 -m pip install --user -r "$SCRIPT_DIR/requirements.txt" || \
    python3 -m pip install --break-system-packages -r "$SCRIPT_DIR/requirements.txt"

  podman pull "$VLLM_IMAGE"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    echo "Run ./start.sh --install-deps"
    exit 1
  fi
}

start_vllm_server() {
  mkdir -p "$HF_HOME"

  echo "Starting vLLM server container on port $VLLM_PORT"
  podman rm -f budget-ai-vllm-server >/dev/null 2>&1 || true
podman run -d \
  --name budget-ai-vllm-server \
  --restart unless-stopped \
  --security-opt=label=disable \
  --device nvidia.com/gpu=all \
  --shm-size=8g \
  -p "$VLLM_PORT:8000" \
  -v "$HF_HOME:/root/.cache/huggingface:Z" \
  -e CUDA_VISIBLE_DEVICES=0 \
  -e HF_HOME=/root/.cache/huggingface \
  -e CUDA_MODULE_LOADING=LAZY \
  -e VLLM_USE_V1=1 \
  "$VLLM_IMAGE" \
    --model "$MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8000 \
    --dtype bfloat16 \
    --max-model-len 8192 \
    --max-num-seqs 4 \
    --gpu-memory-utilization 0.92

  echo "Waiting for vLLM server to become healthy..."
  # vLLM may take longer than llama.cpp to become ready, especially on first run
  # when it needs to download the model from Hugging Face
  for _ in {1..120}; do
    if curl -fsS "http://127.0.0.1:${VLLM_PORT}/health" >/dev/null 2>&1; then
      echo "vLLM server is ready"
      return
    fi
    sleep 2
  done

  echo "vLLM server did not become ready in time"
  exit 1
}

start_fastapi() {
  export VLLM_SERVER_URL="http://127.0.0.1:${VLLM_PORT}"

  if [[ "$DETACHED" == true ]]; then
    echo "Starting FastAPI in detached mode on port $FASTAPI_PORT"
    nohup python3 -m uvicorn api:app --host "$FASTAPI_HOST" --port "$FASTAPI_PORT" > "$SCRIPT_DIR/fastapi.log" 2>&1 &
    echo $! > "$SCRIPT_DIR/fastapi.pid"
    echo "FastAPI PID: $(cat "$SCRIPT_DIR/fastapi.pid")"
    echo "Try: curl -X POST http://127.0.0.1:${FASTAPI_PORT}/generate -H 'Content-Type: application/json' -d '{\"prompt\":\"hello\"}'"
  else
    echo "Starting FastAPI on port $FASTAPI_PORT"
    exec python3 -m uvicorn api:app --host "$FASTAPI_HOST" --port "$FASTAPI_PORT"
  fi
}

if [[ "$INSTALL_DEPS" == true ]]; then
  install_deps
fi

require_cmd python3
require_cmd podman
require_cmd curl

start_vllm_server
start_fastapi
