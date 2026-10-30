"""Private Kinyarwanda text to speech service. Only the Express backend calls it,
with the shared secret in the X-TTS-Secret header."""

import hmac
import io
import os
import wave
from contextlib import asynccontextmanager
from typing import Callable

import numpy as np
from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

from engine import Engine, load_engine

MAX_TEXT_CHARS = 300


class SynthesizeRequest(BaseModel):
    text: str


def to_wav(samples: np.ndarray, sample_rate: int) -> bytes:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(pcm.tobytes())
    return buf.getvalue()


def create_app(secret: str | None = None, engine_factory: Callable[[], Engine] = load_engine) -> FastAPI:
    secret = secret if secret is not None else os.environ.get("TTS_SHARED_SECRET", "")
    if len(secret) < 16:
        # Fail closed: without a proper secret anyone on the network could use the service.
        raise RuntimeError("Set TTS_SHARED_SECRET to a random string of at least 16 characters.")
    expected = secret.encode()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        # Load the model once, before the service accepts requests (so /health only
        # answers once it can synthesize).
        app.state.engine = await run_in_threadpool(engine_factory)
        print(f"TTS model ready: {app.state.engine.model_id}", flush=True)
        yield

    app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware("http")
    async def require_secret(request: Request, call_next):
        if request.url.path != "/health":
            given = request.headers.get("x-tts-secret", "").encode()
            if not hmac.compare_digest(given, expected):
                return JSONResponse({"error": "unauthorized"}, status_code=401)
        return await call_next(request)

    @app.get("/health")
    def health(request: Request):
        return {"ok": True, "model": request.app.state.engine.model_id}

    @app.post("/synthesize")
    async def synthesize(body: SynthesizeRequest, request: Request):
        text = body.text.strip()
        if not text:
            return JSONResponse({"error": "empty_text"}, status_code=400)
        if len(text) > MAX_TEXT_CHARS:
            return JSONResponse({"error": "text_too_long", "max": MAX_TEXT_CHARS}, status_code=413)
        engine: Engine = request.app.state.engine
        try:
            samples = await run_in_threadpool(engine.synthesize, text)
        except ValueError:
            return JSONResponse({"error": "nothing_to_say"}, status_code=422)
        return Response(
            to_wav(samples, engine.sample_rate),
            media_type="audio/wav",
            headers={"x-tts-model": engine.model_id},
        )

    return app
