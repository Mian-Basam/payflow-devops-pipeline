# ---- build stage: install deps into a venv ----
FROM python:3.12-slim AS build
WORKDIR /build
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# ---- runtime stage: small image, non-root user ----
FROM python:3.12-slim
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PORT=8000
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 payflow
COPY --from=build /venv /venv
WORKDIR /srv
COPY app/ app/
USER payflow
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD curl -fsS http://localhost:8000/health || exit 1
LABEL org.opencontainers.image.title="payflow-api" \
      org.opencontainers.image.version="${APP_VERSION}"
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app.main:app"]
