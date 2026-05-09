# Multi-stage build:
#   - builder: install deps into a venv (caches well)
#   - runtime: minimal slim image, non-root user, only what's needed
#
# Final image: ~120 MB. Non-privileged. Healthcheck baked in.

# ─── Stage 1: build dependencies ─────────────────────────────────────
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build
COPY requirements.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip && \
    /opt/venv/bin/pip install -r requirements.txt

# ─── Stage 2: runtime ────────────────────────────────────────────────
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# curl for HEALTHCHECK; tini for proper signal handling
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl tini && \
    rm -rf /var/lib/apt/lists/*

# Non-root user (matches Helm chart's runAsUser: 1000)
RUN useradd --create-home --shell /bin/bash --uid 1000 appuser

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY --chown=appuser:appuser main.py .

USER appuser

EXPOSE 8000

# Liveness check — used by Docker locally and K8s probes (additionally configured in deployment.yaml)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://localhost:8000/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
