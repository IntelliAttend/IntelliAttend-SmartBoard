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


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, max_requests: int = 60, window_seconds: int = 60):
        super().__init__(app)
        self.limiter = SlidingWindowRateLimiter(max_requests, window_seconds)

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if request.url.path.startswith("/api/v1/admin"):
            return await call_next(request)

        allowed, remaining = self.limiter.check(request)
        if not allowed:
            logger.warning(f"Rate limit exceeded for {request.client.host} on {request.url.path}")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many requests. Please slow down.",
                headers={"Retry-After": "60", "X-RateLimit-Remaining": "0"},
            )

        self.limiter.record(request)
        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(self.limiter.max_requests)
        response.headers["X-RateLimit-Remaining"] = str(remaining - 1 if remaining > 0 else 0)
        return response
