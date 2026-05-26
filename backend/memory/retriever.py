import logging
from typing import Optional

import chromadb
from chromadb.config import Settings as ChromaSettings

from config import settings
from memory.store import db

logger = logging.getLogger(__name__)

_chroma_client: Optional[chromadb.PersistentClient] = None


def get_chroma_client() -> chromadb.PersistentClient:
    global _chroma_client
    if _chroma_client is None:
        _chroma_client = chromadb.PersistentClient(
            path=settings.CHROMA_DB_PATH,
            settings=ChromaSettings(
                anonymized_telemetry=False,
                allow_reset=True,
            ),
        )
        logger.info("ChromaDB initialized at %s", settings.CHROMA_DB_PATH)
    return _chroma_client


def get_chroma_collection(user_id: str) -> chromadb.Collection:
    client = get_chroma_client()
    collection_name = _sanitize_collection_name(f"user_{user_id}")
    return client.get_or_create_collection(
        name=collection_name,
        metadata={"hnsw:space": "cosine"},
    )


def retrieve_relevant_memories(
    user_id: str,
    query_text: str,
    n_results: Optional[int] = None,
    min_similarity: Optional[float] = None,
) -> list[dict]:
    n = n_results or settings.MEMORY_RETRIEVAL_COUNT
    threshold = min_similarity or settings.MEMORY_SIMILARITY_THRESHOLD

    try:
        collection = get_chroma_collection(user_id)
        count = collection.count()
        if count == 0:
            return []

        actual_n = min(n, count)
        results = collection.query(
            query_texts=[query_text],
            n_results=actual_n,
            include=["documents", "metadatas", "distances"],
        )

        documents = results["documents"][0] if results.get("documents") else []
        metadatas = results["metadatas"][0] if results.get("metadatas") else []
        distances = results["distances"][0] if results.get("distances") else []
        ids = results["ids"][0] if results.get("ids") else []

        metadata_map = db.get_memory_metadata_map(user_id, ids)
        memories = []
        retrieved_ids = []

        for chroma_id, document, meta, distance in zip(ids, documents, metadatas, distances):
            similarity = 1.0 - float(distance)
            if similarity < threshold:
                continue

            stored_meta = metadata_map.get(chroma_id, {})
            strength = float(stored_meta.get("strength") or meta.get("strength") or 1.0)
            emotional_weight = float(
                stored_meta.get("emotional_weight") or meta.get("emotional_weight") or meta.get("importance") or 0.5
            )

            memories.append({
                "id": chroma_id,
                "title": stored_meta.get("title") or meta.get("title") or _derive_title(document),
                "content": document,
                "emotion_tag": stored_meta.get("emotion_tag") or meta.get("emotion_tag") or "",
                "emotional_weight": emotional_weight,
                "strength": strength,
                "similarity": round(similarity, 3),
            })
            retrieved_ids.append(chroma_id)

        memories.sort(
            key=lambda item: (
                item["similarity"] * 0.55
                + item["emotional_weight"] * 0.25
                + min(item["strength"], 2.5) / 2.5 * 0.20
            ),
            reverse=True,
        )

        db.reinforce_memories(user_id, retrieved_ids)
        return memories

    except Exception as exc:
        logger.error("Memory retrieval failed for user %s: %s", user_id, exc, exc_info=True)
        return []


def get_memory_count(user_id: str) -> int:
    try:
        return get_chroma_collection(user_id).count()
    except Exception:
        return 0


def delete_memory(user_id: str, memory_id: str) -> bool:
    try:
        get_chroma_collection(user_id).delete(ids=[memory_id])
        return True
    except Exception as exc:
        logger.error("Failed to delete memory %s: %s", memory_id, exc)
        return False


def clear_all_memories(user_id: str) -> bool:
    try:
        client = get_chroma_client()
        client.delete_collection(_sanitize_collection_name(f"user_{user_id}"))
        logger.info("Cleared all memories for user %s", user_id)
        return True
    except Exception as exc:
        logger.error("Failed to clear memories for user %s: %s", user_id, exc)
        return False


def format_memories_for_prompt(memories: list[dict]) -> str:
    if not memories:
        return ""

    lines = []
    for memory in memories:
        emotion = f" [{memory['emotion_tag']}]" if memory.get("emotion_tag") else ""
        title = memory.get("title") or "Episode"
        lines.append(f"- {title}{emotion}: {memory['content']}")
    return "\n".join(lines)


def _derive_title(document: str) -> str:
    text = (document or "").strip()
    return text[:80] if text else "Untitled moment"


def _sanitize_collection_name(name: str) -> str:
    return name.replace("_", "-").lower()[:63]
