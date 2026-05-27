import logging
from typing import Optional

from core.summarizer import run_pair_memory_maintenance

logger = logging.getLogger(__name__)


async def maybe_consolidate_narrative(user_id: str, pair_id: str, companion_id: str) -> Optional[str]:
    result = await run_pair_memory_maintenance(
        user_id=user_id,
        pair_id=pair_id,
        companion_id=companion_id,
    )
    if not result:
        return None
    return result.get("summary")
