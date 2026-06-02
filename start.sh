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
LLAMA_PORT="${LLAMA_PORT:?LLAMA_PORT must be set. Copy .env.template to .env and configure it.}"

LLAMA_IMAGE="${LLAMA_IMAGE:?LLAMA_IMAGE must be set. Copy .env.template to .env and configure it.}"
MODEL_NAME="${MODEL_NAME:?MODEL_NAME must be set. Copy .env.template to .env and configure it.}"
MODEL_FILE="${MODEL_FILE:?MODEL_FILE must be set. Copy .env.template to .env and configure it.}"
MODEL_DIR="${MODEL_DIR:-./models}"

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

  podman pull "$LLAMA_IMAGE"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    echo "Run ./start.sh --install-deps"
    exit 1
  fi
}

download_model() {
  mkdir -p "$MODEL_DIR"
  
  local model_path="$MODEL_DIR/$MODEL_FILE"
  
  if [[ -f "$model_path" ]]; then
    echo "Model already exists at $model_path"
    return
  fi
  
  echo "Downloading model $MODEL_NAME ($MODEL_FILE) to $MODEL_DIR..."
  # Use Python with proper argument passing to avoid injection
  python3 << 'PYTHON_SCRIPT'
import sys
from huggingface_hub import hf_hub_download
import os

MODEL_NAME = os.environ['MODEL_NAME']
MODEL_FILE = os.environ['MODEL_FILE']
MODEL_DIR = os.environ['MODEL_DIR']

try:
    hf_hub_download(
        repo_id=MODEL_NAME,
        filename=MODEL_FILE,
        local_dir=MODEL_DIR,
        local_dir_use_symlinks=False
    )
    print('Model downloaded successfully')
except Exception as e:
    print(f'Error downloading model: {e}', file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

start_llama_server() {
  download_model

  echo "Starting llama.cpp server container on port $LLAMA_PORT"
  podman rm -f budget-ai-llama-server >/dev/null 2>&1 || true
  podman run -d \
    --name budget-ai-llama-server \
    --security-opt=label=disable \
    --device nvidia.com/gpu=all \
    -p "$LLAMA_PORT:8080" \
    -v "$MODEL_DIR:/models:Z" \
    "$LLAMA_IMAGE" \
    --model "/models/$MODEL_FILE" \
    --host 0.0.0.0 \
    --port 8080 \
    --n-gpu-layers 99 \
    --ctx-size 8192

  echo "Waiting for llama.cpp server to become healthy..."
  for _ in {1..60}; do
    if curl -fsS "http://127.0.0.1:${LLAMA_PORT}/health" >/dev/null 2>&1; then
      echo "llama.cpp server is ready"
      return
    fi
    sleep 2
  done

  echo "llama.cpp server did not become ready in time"
  exit 1
}

start_fastapi() {
  export LLAMA_SERVER_URL="http://127.0.0.1:${LLAMA_PORT}"

  if [[ "$DETACHED" == true ]]; then
    echo "Starting FastAPI in detached mode on port $FASTAPI_PORT"
    nohup python3 -m uvicorn api:app --host "$FASTAPI_HOST" --port "$FASTAPI_PORT" > "$SCRIPT_DIR/fastapi.log" 2>&1 &
    echo $! > "$SCRIPT_DIR/fastapi.pid"
    echo "FastAPI PID: $(cat "$SCRIPT_DIR/fastapi.pid")"
    cat <<EOF
Try: curl -X POST http://127.0.0.1:${FASTAPI_PORT}/generate \\
  -H 'Content-Type: application/json' \\
  -d '{"messages":[{"role":"user","content":"hello"}]}'
EOF
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

start_llama_server
start_fastapi
