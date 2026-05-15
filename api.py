import json
import logging
import os
from urllib.error import URLError
from urllib.request import Request, urlopen

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field


LLAMA_SERVER_URL = os.getenv("LLAMA_SERVER_URL", "http://127.0.0.1:8080")
TIMEOUT_SECONDS = float(os.getenv("LLAMA_SERVER_TIMEOUT", "120"))

logger = logging.getLogger("budget-ai")

app = FastAPI(title="budget-ai-llama.cpp", version="0.1.0")


class GenerateRequest(BaseModel):
    prompt: str = Field(..., min_length=1)
    max_tokens: int = Field(default=128, ge=1, le=512)
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/generate")
def generate(req: GenerateRequest) -> StreamingResponse:
    payload = {
        "prompt": req.prompt,
        "n_predict": req.max_tokens,
        "temperature": req.temperature,
        "stream": True,
    }

    body = json.dumps(payload).encode("utf-8")
    request = Request(
        f"{LLAMA_SERVER_URL.rstrip('/')}/completion",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    # Verify the upstream server is reachable before starting the stream so
    # that connection errors can be surfaced as a proper 502 response.
    try:
        response = urlopen(request, timeout=TIMEOUT_SECONDS)
    except URLError as exc:
        raise HTTPException(status_code=502, detail=f"Failed to reach llama.cpp server: {exc}") from exc

    def stream_generator():
        try:
            with response:
                while True:
                    try:
                        chunk = response.readline()
                    except OSError as exc:
                        logger.error("Error reading from llama.cpp stream: %s", exc)
                        yield f"data: {json.dumps({'error': str(exc)})}\n\n".encode()
                        break
                    if not chunk:
                        break
                    yield chunk
        except Exception as exc:
            logger.error("Unexpected error in stream_generator: %s", exc)

    return StreamingResponse(stream_generator(), media_type="text/event-stream")
