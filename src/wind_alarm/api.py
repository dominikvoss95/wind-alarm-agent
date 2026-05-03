"""
FastAPI server for exposing wind measurements with security best practices.
"""
import os
import time
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, Depends, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from typing import Optional
from datetime import datetime, timezone
from collections import defaultdict
from threading import Lock

from wind_alarm import store

API_KEY = os.environ.get("API_KEY", "dev-key-change-in-production")
RATE_LIMIT_REQUESTS = 60
RATE_LIMIT_WINDOW = 60

rate_limits: dict[str, list[float]] = defaultdict(list)
rate_lock = Lock()


def check_rate_limit(client_id: str) -> bool:
    """Check if client exceeds rate limit."""
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW

    with rate_lock:
        rate_limits[client_id] = [
            ts for ts in rate_limits[client_id] if ts > window_start
        ]
        if len(rate_limits[client_id]) >= RATE_LIMIT_REQUESTS:
            return False
        rate_limits[client_id].append(now)
        return True


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events."""
    print(f"Starting Wind Alarm API (version=1.0.0)")
    yield
    print("Shutting down Wind Alarm API")


app = FastAPI(
    title="Wind Alarm API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    """Add security headers to response."""
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'self'"
    return response


@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    """Rate limiting middleware."""
    client_id = request.client.host if request.client else "unknown"

    if request.url.path.startswith(("/trigger", "/measurements")):
        if not check_rate_limit(client_id):
            return JSONResponse(
                status_code=429,
                content={"detail": "Rate limit exceeded"},
            )

    return await call_next(request)


api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def verify_api_key(api_key: str = Security(api_key_header)) -> str:
    """Verify API key."""
    if api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return api_key


class MeasurementResponse(BaseModel):
    location: str
    base_wind: float
    gust: float
    observed_at: Optional[str] = None
    fetched_at: Optional[str] = None
    fetch_status: str
    is_fresh: bool
    threshold_exceeded: bool
    error_message: str
    updated_at: str


class TriggerRequest(BaseModel):
    threshold: float = Field(default=12.0, ge=0.0, le=50.0)
    freshness: int = Field(default=60, ge=1, le=1440)

    @field_validator("threshold", "freshness", mode="before")
    @classmethod
    def validate_values(cls, v):
        if v is None:
            return v
        return v


class HealthResponse(BaseModel):
    status: str
    timestamp: str


@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat()
    )


@app.get("/measurements/{location}", response_model=MeasurementResponse)
async def get_measurement(location: str, _: str = Depends(verify_api_key)):
    if not location or not location.replace("_", "").replace("-", "").isalnum():
        raise HTTPException(status_code=400, detail="Invalid location format")

    measurement = store.get_measurement(location)
    if not measurement:
        raise HTTPException(status_code=404, detail=f"No measurement found for location: {location}")
    return MeasurementResponse(location=location, **measurement)


@app.get("/measurements", response_model=dict[str, MeasurementResponse])
async def get_all_measurements(_: str = Depends(verify_api_key)):
    all_data = store.get_all_measurements()
    return {
        location: MeasurementResponse(location=location, **data)
        for location, data in all_data.items()
    }


@app.post("/trigger/{location}")
async def trigger_measurement(
    location: str,
    request: TriggerRequest = Depends(),
    _: str = Depends(verify_api_key),
):
    if not location or not location.replace("_", "").replace("-", "").isalnum():
        raise HTTPException(status_code=400, detail="Invalid location format")

    from wind_alarm.graph import build_wind_alarm_graph
    from wind_alarm.state import WindGraphState
    from wind_alarm.config import config

    location_cfg = config.LOCATIONS.get(location)
    if not location_cfg:
        raise HTTPException(status_code=404, detail=f"Unknown location: {location}")

    app_graph = build_wind_alarm_graph()
    results = []

    for url in location_cfg.get("urls", []):
        state = WindGraphState(
            source_identifier=url,
            location_id=location,
            target_fcm_topic=location_cfg["fcm_topic"],
            threshold_knots=request.threshold,
            freshness_limit_minutes=request.freshness,
        )
        result = app_graph.invoke(state)
        results.append(result)

    best = results[0]
    for r in results:
        if r.get("threshold_exceeded"):
            best = r
            break

    store.set_measurement(location, best)
    return {"location": location, "stored": True, "threshold_exceeded": best.get("threshold_exceeded", False)}