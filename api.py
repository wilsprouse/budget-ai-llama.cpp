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
    LLAMA_SERVER_URL = os.environ["LLAMA_SERVER_URL"]
    TIMEOUT_SECONDS = float(os.environ["LLAMA_SERVER_TIMEOUT"])
    MODEL_NAME = os.environ["MODEL_NAME"]
except KeyError as e:
    raise RuntimeError(
        f"Missing required environment variable: {e}. "
        "Copy .env.template to .env and configure it before running."
    ) from e

logger = logging.getLogger("budget-ai")

app = FastAPI(title="budget-ai-llama", version="0.1.0")

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
    # model field retained for API backward compatibility but not used by llama.cpp
    model: Optional[str] = None
    messages: List[Message]
    max_tokens: Optional[int] = 128
    temperature: Optional[float] = 0.7
    stream: Optional[bool] = True


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/generate")
def generate(req: GenerateRequest) -> StreamingResponse:
    # Convert messages to a single prompt string for llama.cpp
    # llama.cpp expects a single prompt, not chat format
    # Note: This uses a simple format. For models trained with specific chat templates,
    # you may need to adjust the formatting (e.g., [INST], <|im_start|>, etc.)
    prompt_parts = []
    for msg in req.messages:
        if msg.role == "system":
            prompt_parts.append(f"System: {msg.content}")
        elif msg.role == "user":
            prompt_parts.append(f"User: {msg.content}")
        elif msg.role == "assistant":
            prompt_parts.append(f"Assistant: {msg.content}")
    
    prompt = "\n".join(prompt_parts)
    # Only add Assistant prompt if the last message is from user
    # If conversation ends with assistant message, model will continue from there
    if req.messages and req.messages[-1].role == "user":
        prompt += "\nAssistant:"
    
    # llama.cpp /completion endpoint format
    payload = {
        "prompt": prompt,
        "n_predict": req.max_tokens,
        "temperature": req.temperature,
        "stream": req.stream,
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
                    yield chunk  # <-- raw llama.cpp SSE passthrough
        except Exception as exc:
            logger.error("Unexpected error in stream_generator: %s", exc)

    return StreamingResponse(stream_generator(), media_type="text/event-stream")
