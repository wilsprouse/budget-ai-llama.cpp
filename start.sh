#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DETACHED=false
INSTALL_DEPS=false

FASTAPI_HOST="${FASTAPI_HOST:-0.0.0.0}"
FASTAPI_PORT="${FASTAPI_PORT:-8000}"
LLAMA_PORT="${LLAMA_PORT:-8080}"

LLAMA_IMAGE="${LLAMA_IMAGE:-ghcr.io/ggerganov/llama.cpp:server}"
MODEL_DIR="${MODEL_DIR:-$SCRIPT_DIR/models}"
MODEL_NAME="${MODEL_NAME:-tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf}"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

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

start_llama_server() {
  mkdir -p "$MODEL_DIR"

  if [[ ! -f "$MODEL_PATH" ]]; then
    echo "Downloading TinyLlama model to $MODEL_PATH"
    curl -L --fail --output "$MODEL_PATH" "$MODEL_URL"
  fi

  echo "Starting llama.cpp server container on port $LLAMA_PORT"
  podman rm -f budget-ai-llama-server >/dev/null 2>&1 || true
  podman run -d \
    --name budget-ai-llama-server \
    -p "$LLAMA_PORT:8080" \
    -v "$MODEL_DIR:/models:Z" \
    "$LLAMA_IMAGE" \
    -m "/models/$MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8080 \
    -c 512 \
    -t 1 \
    -ngl 0

  echo "Waiting for llama.cpp server to become healthy..."
  for _ in {1..30}; do
    if curl -fsS "http://127.0.0.1:${LLAMA_PORT}/health" >/dev/null 2>&1; then
      echo "llama.cpp server is ready"
      return
    fi
    sleep 1
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

start_llama_server
start_fastapi
