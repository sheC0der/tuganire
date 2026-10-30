"""The text to speech model. Everything model-specific lives in this file.

To change the voice, set TTS_MODEL (a Railway variable, which the Dockerfile also
uses at build time to bake the weights into the image). Any Hugging Face VITS
checkpoint that transformers' VitsModel can load works as is. A model in another
format (for example a Coqui TTS checkpoint) needs its own engine class here with
the same three members as VitsEngine, returned from load_engine.

Licence: facebook/mms-tts-kin is CC-BY-NC 4.0, so it can't be used commercially.
"""

import os
import re
import threading
from typing import Protocol

import numpy as np

DEFAULT_MODEL = "facebook/mms-tts-kin"
MODEL_ID = os.environ.get("TTS_MODEL", "").strip() or DEFAULT_MODEL


class Engine(Protocol):
    model_id: str
    sample_rate: int

    def synthesize(self, text: str) -> np.ndarray:
        """Returns mono float samples in [-1, 1]. Raises ValueError if the text
        has nothing the model can pronounce."""
        ...


def normalize_text(text: str) -> str:
    """Tidies text before it reaches the tokenizer, which drops characters it
    doesn't know: curly apostrophes (common in Kinyarwanda, as in "y’u Rwanda")
    become straight ones, and runs of whitespace become one space."""
    text = text.replace("’", "'").replace("‘", "'").replace("`", "'")
    return re.sub(r"\s+", " ", text).strip()


class VitsEngine:
    def __init__(self, model_id: str):
        # Imported here so the web layer (and its tests) don't need torch.
        import torch
        from transformers import AutoTokenizer, VitsModel

        threads = os.environ.get("TTS_THREADS")
        if threads:
            torch.set_num_threads(int(threads))
        self._torch = torch
        self._tokenizer = AutoTokenizer.from_pretrained(model_id)
        self._model = VitsModel.from_pretrained(model_id).eval()
        self.model_id = model_id
        self.sample_rate = self._model.config.sampling_rate
        # One synthesis at a time: torch already spreads a single one over the CPU cores.
        self._lock = threading.Lock()
        # The first run is slower; do it now rather than on a learner's first request.
        self.synthesize("Muraho")

    def synthesize(self, text: str) -> np.ndarray:
        inputs = self._tokenizer(normalize_text(text), return_tensors="pt")
        if inputs["input_ids"].shape[-1] == 0:
            raise ValueError("nothing to pronounce")
        with self._lock, self._torch.inference_mode():
            waveform = self._model(**inputs).waveform
        return waveform[0].float().numpy()


def load_engine(model_id: str = MODEL_ID) -> Engine:
    return VitsEngine(model_id)


def download(model_id: str = MODEL_ID) -> None:
    """Fetches the model files into the Hugging Face cache. The Dockerfile runs
    this so the weights are inside the image and startup needs no network."""
    from transformers import AutoTokenizer, VitsModel

    AutoTokenizer.from_pretrained(model_id)
    VitsModel.from_pretrained(model_id)
