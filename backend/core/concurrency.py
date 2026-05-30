import asyncio
import logging
from contextlib import asynccontextmanager

logger = logging.getLogger(__name__)

# Global registry mapping pair_id to asyncio.Lock
_pair_locks: dict[str, asyncio.Lock] = {}
# Lock protecting concurrent access to the registry itself
_registry_lock = asyncio.Lock()


async def get_pair_lock(pair_id: str) -> asyncio.Lock:
    """
    Thread-safe/async-safe resolution of a pair-scoped asyncio.Lock.
    """
    async with _registry_lock:
        if pair_id not in _pair_locks:
            _pair_locks[pair_id] = asyncio.Lock()
        return _pair_locks[pair_id]


@asynccontextmanager
async def pair_lock_context(pair_id: str, timeout: float = 120.0):
    """
    Async context manager that safely acquires and releases a pair-scoped lock.
    Uses timeouts to prevent deadlocks and garbage collects inactive locks.
    """
    lock = await get_pair_lock(pair_id)
    try:
        await asyncio.wait_for(lock.acquire(), timeout=timeout)
    except asyncio.TimeoutError:
        logger.error("Lock acquisition timed out for pair: %s", pair_id)
        raise TimeoutError(f"Concurrency lock acquisition timed out for pair: {pair_id}")

    try:
        yield lock
    finally:
        try:
            lock.release()
        except RuntimeError:
            # In case the lock was already released or not acquired
            pass

        # Cleanup registry to prevent memory leaks for inactive/disposed session locks
        async with _registry_lock:
            if pair_id in _pair_locks:
                active_lock = _pair_locks[pair_id]
                if not active_lock.locked() and not getattr(active_lock, "_waiters", None):
                    _pair_locks.pop(pair_id, None)
                    logger.debug("Garbage collected inactive lock for pair: %s", pair_id)
