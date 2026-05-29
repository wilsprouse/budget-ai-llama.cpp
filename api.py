import json
import logging
import os
from urllib.error import URLError
from urllib.request import Request, urlopen

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field


try:
    VLLM_SERVER_URL = os.environ["VLLM_SERVER_URL"]
    TIMEOUT_SECONDS = float(os.environ["VLLM_SERVER_TIMEOUT"])
    MODEL_NAME = os.environ["MODEL_NAME"]
except KeyError as e:
    raise RuntimeError(
        f"Missing required environment variable: {e}. "
        "Copy .env.template to .env and configure it before running."
    ) from e

logger = logging.getLogger("budget-ai")

app = FastAPI(title="budget-ai-vllm", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class GenerateRequest(BaseModel):
    prompt: str = Field(..., min_length=1)
    max_tokens: int = Field(default=128, ge=1, le=4096)
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/generate")
def generate(req: GenerateRequest) -> StreamingResponse:
    # vLLM uses OpenAI-compatible API format
    payload = {
        "model": MODEL_NAME,
        "messages": [
            {
                "role": "user",
                "content": req.prompt,
            }
        ],
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
        "stream": True,
    }

    body = json.dumps(payload).encode("utf-8")
    request = Request(
        f"{VLLM_SERVER_URL.rstrip('/')}/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    # Verify the upstream server is reachable before starting the stream so
    # that connection errors can be surfaced as a proper 502 response.
    try:
        response = urlopen(request, timeout=TIMEOUT_SECONDS)
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")

        raise HTTPException(
            status_code=502,
            detail={
                "status": exc.code,
                "reason": exc.reason,
                "body": body,
            },
        )

    def stream_generator():
        try:
            with response:
                while True:
                    try:
                        chunk = response.readline()
                    except OSError as exc:
                        logger.error("Error reading from vLLM stream: %s", exc)
                        yield f"data: {json.dumps({'error': str(exc)})}\n\n".encode()
                        break
                    if not chunk:
                        break
                    # vLLM returns SSE format: "data: {...}\n\n"
                    # Parse and reformat to match our API format
                    try:
                        line = chunk.decode('utf-8').strip()
                    except UnicodeDecodeError as exc:
                        logger.error("Error decoding vLLM response: %s", exc)
                        yield f"data: {json.dumps({'error': 'Invalid UTF-8 in response'})}\n\n".encode()
                        break
                    if line.startswith("data: "):
                        data_str = line[6:]  # Remove "data: " prefix
                        if data_str == "[DONE]":
                            break
                        try:
                            data = json.loads(data_str)
                            # Extract the text from vLLM's format
                            if "choices" in data and len(data["choices"]) > 0:
                                text = data["choices"][0].get("text", "")
                                # Reformat to our API format
                                yield f"data: {json.dumps({'content': text})}\n\n".encode()
                        except json.JSONDecodeError:
                            # If we can't parse, just pass through
                            yield chunk
        except Exception as exc:
            logger.error("Unexpected error in stream_generator: %s", exc)

    return StreamingResponse(stream_generator(), media_type="text/event-stream")
