FROM python:3.10-slim-bookworm

LABEL maintainer="wind-alarm-agent"
LABEL description="Wind Alarm Agent - Multi-Location Wind Monitoring System"

# Security: Non-root user
ARG APP_USER=appuser
ARG APP_UID=1000
ARG APP_GID=1000

RUN groupadd --gid "$APP_GID" "$APP_USER" && \
    useradd --uid "$APP_UID" --gid "$APP_GID" --create-home "$APP_USER"

WORKDIR /app

# Security: Install only necessary packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        dumb-init \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -u 1001 -g 0 tini

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY app.py ./
COPY pyproject.toml ./
COPY README.md ./
COPY specs.md ./
COPY config.toml .env.example ./
COPY debugging.md ./

# Security: Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Security: Environment variables for production
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