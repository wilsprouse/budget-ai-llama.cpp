# Migration from vLLM back to llama.cpp

This document describes the migration from vLLM back to llama.cpp to support GGUF quantized models.

## Why llama.cpp?

llama.cpp provides:
- **GGUF support**: Native support for quantized GGUF models from Hugging Face
- **Lower memory usage**: Quantized models (Q4_K_M, Q5_K_M, etc.) use significantly less GPU memory
- **Budget-friendly**: Enables running larger models on smaller GPUs through quantization
- **Fast inference**: Optimized for single-user scenarios with efficient GPU utilization

## Key Changes

### 1. Container Image
- **Before**: `vllm/vllm-openai:latest`
- **After**: `ghcr.io/ggml-org/llama.cpp:server-cuda`

### 2. Model Format
- **Before**: Hugging Face model IDs (e.g., `Qwen/Qwen2.5-Coder-7B-Instruct`)
- **After**: GGUF quantized models from Hugging Face (e.g., `bartowski/Codestral-22B-v0.1-GGUF`)

### 3. Model Storage
- **Before**: Models automatically downloaded from Hugging Face Hub to `./hf_cache/` directory
- **After**: GGUF files downloaded via `huggingface-hub` to `./models/` directory

### 4. API Endpoint
- **Before**: `/v1/chat/completions` endpoint with OpenAI-compatible format
- **After**: `/completion` endpoint with llama.cpp-specific format (with chat message conversion)

### 5. Configuration Variables
Changed environment variables:
- `VLLM_PORT` → `LLAMA_PORT`
- `VLLM_SERVER_URL` → `LLAMA_SERVER_URL`
- `VLLM_SERVER_TIMEOUT` → `LLAMA_SERVER_TIMEOUT`
- `VLLM_IMAGE` → `LLAMA_IMAGE`
- `HF_HOME` → removed (models stored in `MODEL_DIR`)
- `MODEL_NAME` → now uses Hugging Face GGUF repository format
- `MODEL_FILE` → added (specific GGUF file to download, e.g., `Codestral-22B-v0.1-Q4_K_M.gguf`)
- `MODEL_DIR` → added (directory for downloaded models, default: `./models`)

### 6. Startup Time
- **Before**: First run downloads the model from Hugging Face (may take time). Subsequent runs use the cached model.
- **After**: First run downloads the GGUF file from Hugging Face (faster than full model). Subsequent runs start almost instantly.

### 7. Memory Usage
- **Before**: Full precision models require more GPU memory, but vLLM's PagedAttention is more efficient for concurrent requests
- **After**: GGUF quantization (Q4_K_M) significantly reduces memory usage, enabling larger models on smaller GPUs

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

Note: The first run will download the GGUF model file from Hugging Face. This is typically faster than downloading a full precision model.

## API Compatibility

The FastAPI wrapper maintains the same external API format (chat messages), so existing clients don't need changes:

**Request format** (unchanged):
```json
{
  "messages": [
    {"role": "user", "content": "Write a hello world program"}
  ],
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

Internally, the FastAPI wrapper converts chat messages to llama.cpp's prompt format.

## Performance Considerations

### When to use llama.cpp:
- Single user or low concurrency scenarios
- Limited GPU memory (quantized models use 30-50% less memory)
- Budget constraints (run larger models on smaller GPUs)
- Fast startup time is important

### GPU Memory:
llama.cpp is configured with `--n-gpu-layers 99` to offload all layers to GPU. This works well with quantized GGUF models.

### Context Length:
llama.cpp is configured with `--ctx-size 8192` for 8K context window. Adjust based on your needs and GPU memory.

### Quantization Options:
Available quantization levels for Codestral-22B-v0.1 (sizes will vary for other models):
- Q8_0: 23.64GB (highest quality, minimal quality loss)
- Q6_K: 18.25GB (very high quality, recommended for most use cases)
- Q5_K_M: 15.72GB (high quality, good balance)
- Q4_K_M: 13.34GB (good quality, default, best balance of size/quality)
- IQ4_XS: 11.93GB (decent quality, smaller)
- IQ2_XS: 6.64GB (smallest, lowest quality)

To use a different quantization, update `MODEL_FILE` in `.env`:
```bash
MODEL_FILE=Codestral-22B-v0.1-Q6_K.gguf  # For higher quality
```

## Troubleshooting

### Model not downloading:
- Check internet connectivity
- Verify Hugging Face is accessible
- Check disk space in `./models/`
- Ensure `huggingface-hub` is installed: `pip install huggingface-hub`

### Out of memory:
- Use a smaller quantization (e.g., IQ4_XS or IQ2_XS)
- Reduce `--ctx-size` in `start.sh`
- Reduce `--n-gpu-layers` to offload fewer layers to GPU

### Container fails to start:
- Check GPU is available: `nvidia-smi`
- Verify podman can access GPU: `podman run --device nvidia.com/gpu=all nvidia/cuda:12.0-base nvidia-smi`
- Check logs: `podman logs budget-ai-llama-server`

### API format issues:
- The FastAPI wrapper converts chat messages to llama.cpp prompt format
- If you need different prompt formatting, modify the `generate()` function in `api.py`
