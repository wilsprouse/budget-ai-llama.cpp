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
MODEL_DIR="${MODEL_DIR:?MODEL_DIR must be set. Copy .env.template to .env and configure it.}"
MODEL_NAME="${MODEL_NAME:?MODEL_NAME must be set. Copy .env.template to .env and configure it.}"
MODEL_URL="${MODEL_URL:?MODEL_URL must be set. Copy .env.template to .env and configure it.}"
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
    echo "Downloading model parts to $MODEL_DIR"
    
    # Download all split parts of the model
    # The 32B model is split into 3 parts: 00001-of-00003, 00002-of-00003, 00003-of-00003
    for part in 00001-of-00003 00002-of-00003 00003-of-00003; do
      part_filename="${MODEL_NAME%.gguf}-${part}.gguf"
      part_path="$MODEL_DIR/$part_filename"
      part_url="${MODEL_URL}-${part}.gguf"
      
      if [[ ! -f "$part_path" ]]; then
        echo "Downloading $part_filename from $part_url"
        curl -L --fail --output "$part_path" "$part_url"
      else
        echo "Part $part_filename already exists, skipping download"
      fi
    done
    
    # Merge the parts using llama-gguf-split (available in the llama.cpp container)
    echo "Merging model parts into $MODEL_PATH"
    first_part="${MODEL_NAME%.gguf}-00001-of-00003.gguf"
    podman run --rm \
      -v "$MODEL_DIR:/models:Z" \
      "$LLAMA_IMAGE" \
      llama-gguf-split --merge "/models/$first_part" "/models/$MODEL_NAME"
    
    # Clean up the split files after successful merge
    if [[ -f "$MODEL_PATH" ]]; then
      echo "Merge successful, cleaning up split files"
      rm -f "$MODEL_DIR/${MODEL_NAME%.gguf}"-*-of-*.gguf
    else
      echo "ERROR: Merge failed, $MODEL_PATH not created"
      exit 1
    fi
  fi

  echo "Starting llama.cpp server container on port $LLAMA_PORT"
  podman rm -f budget-ai-llama-server >/dev/null 2>&1 || true
  podman run -d \
    --name budget-ai-llama-server \
    --device nvidia.com/gpu=all \
    -p "$LLAMA_PORT:8080" \
    -v "$MODEL_DIR:/models:Z" \
    "$LLAMA_IMAGE" \
    -m "/models/$MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8080 \
    -c 4096 \
    -t $(nproc) \
    -ngl 999 \
    --parallel 2

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
