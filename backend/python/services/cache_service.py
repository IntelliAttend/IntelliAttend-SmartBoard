import logging
import os
import json
from typing import Optional

logger = logging.getLogger("IntelliAttend.Cache")

try:
    import redis.asyncio as aioredis
    _redis_available = True
except ImportError:
    _redis_available = False

class CacheService:
    _client = None
    _local_fallback: dict = {}
    _warned = False

    @classmethod
    async def get_client(cls):
        if cls._client is None:
            url = os.getenv("REDIS_URL", "redis://localhost:6379")
            if _redis_available and url:
                try:
                    cls._client = aioredis.from_url(url, decode_responses=True)
                    await cls._client.ping()
                except Exception as e:
                    if not cls._warned:
                        logger.warning(f"Redis unavailable ({e}). Using in-memory fallback — data will be lost on restart.")
                        cls._warned = True
                    cls._client = None
        return cls._client

    @classmethod
    async def get(cls, key: str) -> Optional[str]:
        client = await cls.get_client()
        if client:
            try:
                return await client.get(key)
            except Exception:
                return cls._local_fallback.get(key)
        return cls._local_fallback.get(key)

    @classmethod
    async def set(cls, key: str, value: str, ttl: int = 10860) -> None:
        client = await cls.get_client()
        if client:
            try:
                await client.setex(key, ttl, value)
                return
            except Exception:
                pass
        if not cls._warned:
            logger.warning("Redis unavailable — caching in memory only. Data will be lost on restart.")
            cls._warned = True
        cls._local_fallback[key] = value

    @classmethod
    async def delete(cls, key: str) -> None:
        client = await cls.get_client()
        if client:
            try:
                await client.delete(key)
                return
            except Exception:
                pass
        cls._local_fallback.pop(key, None)

    @classmethod
    async def set_json(cls, key: str, data: dict, ttl: int = 10860) -> None:
        await cls.set(key, json.dumps(data), ttl)

    @classmethod
    async def get_json(cls, key: str) -> Optional[dict]:
        raw = await cls.get(key)
        if raw:
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                pass
        return None
