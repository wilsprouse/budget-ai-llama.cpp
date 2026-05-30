import json
import logging
import os
from urllib.error import URLError, HTTPError
from urllib.request import Request, urlopen

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import List, Optional, Literal


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

class Message(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str

class GenerateRequest(BaseModel):
    model: Optional[str] = "TheBloke/Mistral-7B-Instruct-v0.3-AWQ"
    messages: List[Message]
    max_tokens: Optional[int] = 128
    temperature: Optional[float] = 0.7
    stream: Optional[bool] = True


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/generate")
def generate(req: GenerateRequest) -> StreamingResponse:
    # vLLM uses OpenAI-compatible API format
    payload = {
        "model": req.model,
        "messages": [msg.model_dump() for msg in req.messages],
        "max_tokens": req.max_tokens,
        "temperature": req.temperature,
        "stream": req.stream,
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
                    chunk = response.readline()
                    if not chunk:
                        break
                    yield chunk  # <-- raw vLLM SSE passthrough
        except Exception as exc:
            logger.error("Unexpected error in stream_generator: %s", exc)

    return StreamingResponse(stream_generator(), media_type="text/event-stream")
