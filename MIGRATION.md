# Migration from llama.cpp to vLLM

This document describes the migration from llama.cpp to vLLM and the key differences.

## Why vLLM?

vLLM provides:
- **Better concurrency**: PagedAttention algorithm enables efficient memory sharing across requests
- **Higher throughput**: Optimized for serving multiple users simultaneously
- **OpenAI-compatible API**: Standard interface that's widely supported
- **Continuous batching**: Processes multiple requests efficiently

## Key Changes

### 1. Container Image
- **Before**: `ghcr.io/ggml-org/llama.cpp:server-cuda`
- **After**: `vllm/vllm-openai:latest`

### 2. Model Format
- **Before**: GGUF quantized models (e.g., `qwen2.5-coder-7b-instruct-q4_k_m.gguf`)
- **After**: Hugging Face model IDs (e.g., `Qwen/Qwen2.5-Coder-7B-Instruct`)

### 3. Model Storage
- **Before**: Models downloaded manually via curl to `./models/` directory
- **After**: Models automatically downloaded from Hugging Face Hub to `./hf_cache/` directory

### 4. API Endpoint
- **Before**: `/completion` endpoint with llama.cpp-specific format
- **After**: `/v1/completions` endpoint with OpenAI-compatible format

### 5. Configuration Variables
Changed environment variables:
- `LLAMA_PORT` → `VLLM_PORT`
- `LLAMA_SERVER_URL` → `VLLM_SERVER_URL`
- `LLAMA_SERVER_TIMEOUT` → `VLLM_SERVER_TIMEOUT`
- `LLAMA_IMAGE` → `VLLM_IMAGE`
- `MODEL_DIR` → removed (models cached in `HF_HOME`)
- `MODEL_URL` → removed (models downloaded from Hugging Face)
- `MODEL_NAME` → now uses Hugging Face model ID format

### 6. Startup Time
- **Before**: Fast startup after initial model download
- **After**: First run will download the model from Hugging Face (may take time). Subsequent runs use the cached model.

### 7. Memory Usage
- **Before**: GGUF quantization (Q4_K_M) reduced memory usage
- **After**: Full precision models require more GPU memory, but vLLM's PagedAttention is more efficient for concurrent requests

## Migration Steps

1. Update your `.env` file from `.env.template`:
   ```bash
   cp .env.template .env
   ```

2. Install/update dependencies:
   ```bash
   ./start.sh --install-deps
   ```

3. Start the services:
   ```bash
   ./start.sh
   ```

Note: The first run will download the model from Hugging Face, which may take several minutes depending on your internet connection.

## API Compatibility

The FastAPI wrapper maintains the same external API format, so existing clients don't need changes:

**Request format** (unchanged):
```json
{
  "prompt": "Write a hello world program",
  "max_tokens": 128,
  "temperature": 0.7
}
```

**Response format** (unchanged):
```
data: {"content": "Hello"}
data: {"content": " world"}
...
```

## Performance Considerations

### When to use vLLM:
- Multiple concurrent users
- High request throughput requirements
- Batch processing scenarios
- Production deployments

### GPU Memory:
vLLM is configured with `--gpu-memory-utilization 0.9` to use 90% of available GPU memory. Adjust this in `start.sh` if needed.

### Context Length:
vLLM is configured with `--max-model-len 8192` for 8K context window. Adjust based on your needs and GPU memory.

## Troubleshooting

### Model not downloading:
- Check internet connectivity
- Verify Hugging Face is accessible
- Check disk space in `./hf_cache/`

### Out of memory:
- Reduce `--max-model-len` in `start.sh`
- Reduce `--gpu-memory-utilization` in `start.sh`
- Use a smaller model (e.g., `Qwen/Qwen2.5-Coder-3B-Instruct`)

### Container fails to start:
- Check GPU is available: `nvidia-smi`
- Verify podman can access GPU: `podman run --device nvidia.com/gpu=all nvidia/cuda:12.0-base nvidia-smi`
- Check logs: `podman logs budget-ai-vllm-server`
