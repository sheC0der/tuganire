import io
import wave

import numpy as np
import pytest
from fastapi.testclient import TestClient

from app import MAX_TEXT_CHARS, create_app
from engine import normalize_text

SECRET = "test-secret-0123456789"


class FakeEngine:
    model_id = "fake/model"
    sample_rate = 16000

    def __init__(self):
        self.texts = []

    def synthesize(self, text):
        self.texts.append(text)
        if text == "123":
            raise ValueError("nothing to pronounce")
        return np.linspace(-1, 1, 1600, dtype=np.float32)


@pytest.fixture
def engine():
    return FakeEngine()


@pytest.fixture
def client(engine):
    with TestClient(create_app(secret=SECRET, engine_factory=lambda: engine)) as c:
        yield c


def post(client, text, secret=SECRET):
    headers = {"x-tts-secret": secret} if secret is not None else {}
    return client.post("/synthesize", json={"text": text}, headers=headers)


def test_health_needs_no_secret(client):
    assert client.get("/health").json() == {"ok": True, "model": "fake/model"}


def test_rejects_missing_or_wrong_secret(client, engine):
    assert post(client, "Muraho", secret=None).status_code == 401
    assert post(client, "Muraho", secret="wrong").status_code == 401
    assert engine.texts == []


def test_returns_wav(client, engine):
    res = post(client, "  Muraho  ")
    assert res.status_code == 200
    assert res.headers["content-type"] == "audio/wav"
    assert res.headers["x-tts-model"] == "fake/model"
    with wave.open(io.BytesIO(res.content)) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()) == (1, 2, 16000, 1600)
    assert engine.texts == ["Muraho"]


def test_text_limits(client, engine):
    assert post(client, "   ").status_code == 400
    assert post(client, "a" * (MAX_TEXT_CHARS + 1)).status_code == 413
    assert post(client, "123").status_code == 422
    assert client.post("/synthesize", json={}, headers={"x-tts-secret": SECRET}).status_code == 422


def test_refuses_to_start_without_a_real_secret():
    with pytest.raises(RuntimeError):
        create_app(secret="", engine_factory=FakeEngine)


def test_normalize_text():
    assert normalize_text("Murakaza neza mu  Rwanda,\ny’u Rwanda") == "Murakaza neza mu Rwanda, y'u Rwanda"
