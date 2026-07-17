import time
import logging
from collections import defaultdict
from typing import Dict, List, Tuple
from fastapi import Request, Response, HTTPException, status
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

logger = logging.getLogger("IntelliAttend")


class SlidingWindowRateLimiter:
    def __init__(self, max_requests: int = 60, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._buckets: Dict[str, List[float]] = defaultdict(list)

    def _key(self, request: Request) -> str:
        ip = request.client.host if request.client else "unknown"
        device_id = request.headers.get("X-Device-ID", "")
        return f"{ip}:{device_id}"

    def _trim(self, key: str, now: float) -> None:
        cutoff = now - self.window_seconds
        self._buckets[key] = [t for t in self._buckets[key] if t > cutoff]
        if not self._buckets[key]:
            del self._buckets[key]

    def check(self, request: Request) -> Tuple[bool, int]:
        now = time.time()
        key = self._key(request)
        self._trim(key, now)
        count = len(self._buckets.get(key, []))
        allowed = count < self.max_requests
        return allowed, self.max_requests - count

    def record(self, request: Request) -> None:
        now = time.time()
        key = self._key(request)
        self._buckets[key].append(now)


# ─── Rate Limit Tiers ───────────────────────────────────────────────────────
#
# Each endpoint category gets a tailored limit based on its threat model
# and expected legitimate traffic volume.
#
# | Category      | Limit      | Rationale
# |---------------|------------|------------------------------------------
# | health        | 120/min    | Load balancers probe every 5-10s; 120/min
# |               |            | allows ~12 LBs without triggering.
# | auth          | 5/min      | Login/registration should be rare per IP.
# |               |            | Brute-force protection is primary goal.
# | ticket        | 10/min     | WebSocket ticket requests are per-session.
# |               |            | Slightly more generous than auth.
# | general       | 60/min     | Heartbeats, telemetry, config — normal
# |               |            | kiosk traffic. 1 req/min per board is
# |               |            | typical; 60/min accommodates bursts.
# | admin         | exempt     | Admin dashboard is behind Firebase auth
# |               |            | + RBAC. Rate limiting adds no value here.
# ─────────────────────────────────────────────────────────────────────────────


class RateLimitMiddleware(BaseHTTPMiddleware):
    _HEALTH_LIMIT = 120       # Load balancer probes (every 5-10s)
    _AUTH_LIMIT = 5           # Login / registration brute-force protection
    _TICKET_LIMIT = 10        # WebSocket ticket requests
    _GENERAL_LIMIT = 60       # Heartbeats, telemetry, config (default)
    _WINDOW = 60              # All tiers use a 60-second sliding window

    def __init__(self, app, max_requests: int = 60, window_seconds: int = 60):
        super().__init__(app)
        self._health_limiter = SlidingWindowRateLimiter(self._HEALTH_LIMIT, self._WINDOW)
        self._auth_limiter = SlidingWindowRateLimiter(self._AUTH_LIMIT, self._WINDOW)
        self._ticket_limiter = SlidingWindowRateLimiter(self._TICKET_LIMIT, self._WINDOW)
        self._general_limiter = SlidingWindowRateLimiter(max_requests, window_seconds)

    def _select_limiter(self, path: str) -> Tuple[SlidingWindowRateLimiter, int]:
        """Return (limiter, display_limit) for the given path."""
        if path == "/health":
            return self._health_limiter, self._HEALTH_LIMIT
        if path.startswith("/api/v1/device/register"):
            return self._auth_limiter, self._AUTH_LIMIT
        if path.startswith("/api/v1/websocket/ticket"):
            return self._ticket_limiter, self._TICKET_LIMIT
        return self._general_limiter, self._GENERAL_LIMIT

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        path = request.url.path

        # Admin routes are exempt — protected by Firebase auth + RBAC.
        if path.startswith("/api/v1/admin"):
            return await call_next(request)

        limiter, limit = self._select_limiter(path)

        allowed, remaining = limiter.check(request)
        if not allowed:
            logger.warning(f"Rate limit exceeded for {request.client.host} on {path}")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please slow down.",
                headers={"Retry-After": "60", "X-RateLimit-Remaining": "0"},
            )

        limiter.record(request)
        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(limit)
        response.headers["X-RateLimit-Remaining"] = str(remaining - 1 if remaining > 0 else 0)
        return response
