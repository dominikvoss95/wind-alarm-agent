FROM python:3.10-slim-bookworm

LABEL maintainer="wind-alarm-agent"
LABEL description="Wind Alarm Agent - Multi-Location Wind Monitoring System"

# Setup non-root user
ARG APP_USER=appuser
ARG APP_UID=1000
ARG APP_GID=1000

RUN groupadd --gid "$APP_GID" "$APP_USER" && \
    useradd --uid "$APP_UID" --gid "$APP_GID" --create-home "$APP_USER"

WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

# Copy application source
COPY src/ ./src/
COPY app.py ./
COPY pyproject.toml ./
COPY README.md ./
COPY specs.md ./
COPY config.toml .env.example ./
COPY debugging.md ./

# Permissions
RUN chown -R appuser:appuser /app

USER appuser

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV LOG_LEVEL=INFO

# Expose API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Use tini as init system
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["python", "app.py", "--api"]