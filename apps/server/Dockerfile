# Build from the repo root so the image can include both the API server
# (apps/server) and the web client it serves (apps/web):
#   docker build -f apps/server/Dockerfile .

# ---- builder ----
FROM python:3.12-slim AS builder
ENV PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1
WORKDIR /build
COPY apps/server/requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

# ---- runtime ----
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PATH=/install/bin:$PATH \
    PYTHONPATH=/install/lib/python3.12/site-packages
RUN useradd -r -u 1000 app && \
    apt-get update && apt-get install -y --no-install-recommends libpq5 && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /data/backups && chown app:app /data/backups
COPY --from=builder /install /install
# Same layout as the repo: /app/server/app (Python) next to /app/web (SPA)
# and /app/packages/core (the shared JavaScript core).
COPY apps/server/app /app/server/app
COPY apps/web /app/web
# The shared JavaScript core, run by app/jscore.py (#233).
COPY packages/core/walletweather-core.js /app/packages/core/walletweather-core.js
WORKDIR /app/server
USER app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
