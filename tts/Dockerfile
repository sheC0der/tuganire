# syntax=docker/dockerfile:1
# Private Kinyarwanda text to speech, called only by the Express backend over
# Railway's private network. Deployed as a second Railway service whose root
# directory is /tts (see README.md).

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HF_HOME=/opt/hf

WORKDIR /app

# The CPU-only build of torch is a fraction of the size of the default CUDA one.
RUN pip install torch==2.15.0 --index-url https://download.pytorch.org/whl/cpu
COPY requirements.txt .
RUN pip install -r requirements.txt

# Bake the model weights into the image, so the service starts without needing
# Hugging Face. Railway passes the TTS_MODEL service variable here if it's set;
# otherwise engine.py's default is used.
ARG TTS_MODEL
COPY engine.py .
RUN TTS_MODEL="$TTS_MODEL" python -c "import engine; engine.download()"

COPY app.py serve.py ./

ENV HF_HUB_OFFLINE=1
RUN useradd --system --uid 10001 tts && chown -R tts /opt/hf
USER tts

# TTS_SHARED_SECRET is read at runtime only; never pass it as a build arg.
# serve.py listens on PORT (default 8000) over IPv6, which Railway's private
# network uses, and IPv4.
EXPOSE 8000
CMD ["python", "serve.py"]
