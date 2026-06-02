import hashlib
import logging
from datetime import datetime
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


def get_chroma_collection(pair_id: str, user_id: Optional[str] = None) -> chromadb.Collection:
    client = get_chroma_client()
    collection_name = _collection_name_for_pair(pair_id)
    collection = client.get_or_create_collection(
        name=collection_name,
        metadata={"hnsw:space": "cosine"},
    )

    if user_id:
        _migrate_legacy_user_collection(user_id=user_id, pair_id=pair_id, target_collection=collection)

    return collection


def retrieve_relevant_memories(
    pair_id: str,
    query_text: str,
    user_id: Optional[str] = None,
    n_results: Optional[int] = None,
    min_similarity: Optional[float] = None,
) -> list[dict]:
    n = n_results or settings.MEMORY_RETRIEVAL_COUNT
    threshold = min_similarity or settings.MEMORY_SIMILARITY_THRESHOLD

    logger.info("ChromaDB Query for semantic retrieval: '%s'", query_text)

    try:
        collection = get_chroma_collection(pair_id=pair_id, user_id=user_id)
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

        metadata_map = db.get_memory_metadata_map(pair_id, ids)
        memories = []
        retrieved_ids = []

        for chroma_id, document, meta, distance in zip(ids, documents, metadatas, distances):
            similarity = 1.0 - float(distance)
            if similarity < threshold:
                continue

            stored_meta = metadata_map.get(chroma_id, {})
            if int(stored_meta.get("archived") or 0) == 1:
                continue
            strength = float(stored_meta.get("strength") or meta.get("strength") or 1.0)
            emotional_weight = float(
                stored_meta.get("emotional_weight") or meta.get("emotional_weight") or meta.get("importance") or 0.5
            )
            recency = _memory_recency_score(stored_meta)

            memories.append({
                "id": chroma_id,
                "title": stored_meta.get("title") or meta.get("title") or _derive_title(document),
                "content": document,
                "emotion_tag": stored_meta.get("emotion_tag") or meta.get("emotion_tag") or "",
                "emotional_weight": emotional_weight,
                "strength": strength,
                "recency": recency,
                "similarity": round(similarity, 3),
            })
            retrieved_ids.append(chroma_id)

        def _calculate_rank(item: dict) -> float:
            is_unresolved = str(item.get("emotion_tag") or "").lower() in {
                "sad", "anxious", "grief", "anger", "lonely", "overwhelmed"
            }
            unresolved_bonus = 0.10 if is_unresolved else 0.0
            
            return (
                item["similarity"] * 0.35
                + item["emotional_weight"] * 0.30
                + min(item["strength"], 3.0) / 3.0 * 0.15
                + item["recency"] * 0.10
                + unresolved_bonus
            )

        memories.sort(
            key=_calculate_rank,
            reverse=True,
        )

        db.reinforce_memories(pair_id, retrieved_ids)
        return memories

    except Exception as exc:
        logger.error("Memory retrieval failed for pair %s: %s", pair_id, exc, exc_info=True)
        return []


def get_memory_count(pair_id: str, user_id: Optional[str] = None) -> int:
    try:
        return get_chroma_collection(pair_id=pair_id, user_id=user_id).count()
    except Exception:
        return 0


def delete_memory(pair_id: str, memory_id: str, user_id: Optional[str] = None) -> bool:
    try:
        get_chroma_collection(pair_id=pair_id, user_id=user_id).delete(ids=[memory_id])
        return True
    except Exception as exc:
        logger.error("Failed to delete memory %s: %s", memory_id, exc)
        return False


def update_memory_document(
    pair_id: str,
    memory_id: str,
    *,
    content: str,
    title: Optional[str] = None,
    user_id: Optional[str] = None,
) -> bool:
    try:
        collection = get_chroma_collection(pair_id=pair_id, user_id=user_id)
        metadata = {}
        if title:
            metadata["title"] = title
        collection.update(
            ids=[memory_id],
            documents=[content],
            metadatas=[metadata] if metadata else None,
        )
        return True
    except Exception as exc:
        logger.error("Failed to update memory %s: %s", memory_id, exc)
        return False


def clear_all_memories(pair_id: str) -> bool:
    try:
        client = get_chroma_client()
        client.delete_collection(_collection_name_for_pair(pair_id))
        logger.info("Cleared all memories for pair %s", pair_id)
        return True
    except Exception as exc:
        logger.error("Failed to clear memories for pair %s: %s", pair_id, exc)
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


def _collection_name_for_pair(pair_id: str) -> str:
    digest = hashlib.sha256(pair_id.encode("utf-8")).hexdigest()
    return f"pair-{digest[:24]}"


def _legacy_collection_name_for_user(user_id: str) -> str:
    return f"user-{user_id.replace('_', '-').lower()[:58]}"


def _memory_recency_score(stored_meta: dict) -> float:
    anchor = stored_meta.get("last_retrieved_at") or stored_meta.get("created_at")
    if not anchor:
        return 0.2
    try:
        then = datetime.fromisoformat(str(anchor))
    except ValueError:
        return 0.2

    age_days = max(0.0, (datetime.utcnow() - then).total_seconds() / 86400.0)
    if age_days <= 2:
        return 1.0
    if age_days <= 7:
        return 0.82
    if age_days <= 21:
        return 0.58
    if age_days <= 60:
        return 0.34
    return 0.18


def _migrate_legacy_user_collection(
    user_id: str,
    pair_id: str,
    target_collection: chromadb.Collection,
) -> None:
    client = get_chroma_client()
    legacy_name = _legacy_collection_name_for_user(user_id)

    if legacy_name == target_collection.name:
        return

    try:
        legacy = client.get_collection(legacy_name)
    except Exception:
        return

    if target_collection.count() > 0:
        return

    payload = legacy.get(include=["documents", "metadatas"])
    ids = payload.get("ids") or []
    if not ids:
        return

    target_collection.add(
        ids=ids,
        documents=payload.get("documents") or [],
        metadatas=payload.get("metadatas") or [],
    )
    logger.info("Migrated legacy Chroma collection %s -> %s", legacy_name, target_collection.name)
