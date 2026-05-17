# =============================================================================
# memory/retriever.py — ChromaDB Semantic Memory Retrieval
# =============================================================================
#
# PURPOSE:
#   Manages the ChromaDB vector database for EPISODIC memory storage and
#   semantic retrieval. When Nova needs to remember relevant past moments,
#   this is what searches through them.
#
# HOW CHROMADB WORKS (simplified):
#   1. You store text ("User's dog Mango died last year")
#   2. ChromaDB converts it to a vector (list of numbers representing meaning)
#   3. When you search ("tell me about my dog"), ChromaDB finds stored memories
#      with similar meaning — even if the exact words don't match
#   4. You get back the most semantically relevant memories
#
# WHY TWO MEMORY SYSTEMS:
#   - SQLite stores FACTS (always known, always in context)
#   - ChromaDB stores EPISODES (retrieved when relevant, not always)
#   This keeps prompts focused — you don't want to dump 200 memories every time.
#
# COLLECTION STRATEGY:
#   Each user gets their own ChromaDB collection. This keeps memories isolated
#   and makes per-user queries fast. Collection name = "user_{user_id}".
#
# EMBEDDING MODEL:
#   Using ChromaDB's default: "all-MiniLM-L6-v2" (runs locally, free, fast).
#   No API needed for embeddings — this is fully offline.
#
# USAGE:
#   from memory.retriever import retrieve_relevant_memories
#   memories = await retrieve_relevant_memories(user_id, "I'm stressed about work")
# =============================================================================

import logging
from typing import Optional

import chromadb
from chromadb.config import Settings as ChromaSettings

from config import settings

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# ChromaDB Client — singleton, initialized once at startup
# ---------------------------------------------------------------------------

_chroma_client: Optional[chromadb.PersistentClient] = None


def get_chroma_client() -> chromadb.PersistentClient:
    """
    Returns the ChromaDB client (creates it on first call).
    PersistentClient = saves to disk (unlike in-memory which resets on restart).
    """
    global _chroma_client
    if _chroma_client is None:
        _chroma_client = chromadb.PersistentClient(
            path=settings.CHROMA_DB_PATH,
            settings=ChromaSettings(
                anonymized_telemetry=False,   # Don't send usage data to Chroma
                allow_reset=True,
            )
        )
        logger.info(f"ChromaDB initialized at {settings.CHROMA_DB_PATH}")
    return _chroma_client


def get_chroma_collection(user_id: str) -> chromadb.Collection:
    """
    Returns (or creates) the ChromaDB collection for a specific user.

    Each user has their own collection for isolation and query performance.
    Collection name is sanitized because ChromaDB has naming rules.
    """
    client = get_chroma_client()
    collection_name = _sanitize_collection_name(f"user_{user_id}")

    # get_or_create_collection = safe to call every time
    collection = client.get_or_create_collection(
        name=collection_name,
        metadata={"hnsw:space": "cosine"},    # Cosine similarity (best for text)
    )
    return collection


# ---------------------------------------------------------------------------
# Main retrieval function
# ---------------------------------------------------------------------------

def retrieve_relevant_memories(
    user_id: str,
    query_text: str,
    n_results: int = None,
    min_similarity: float = None,
) -> list[dict]:
    """
    Finds the most semantically relevant memories for a given query.

    Called by context_builder.py before every LLM call.

    Args:
        user_id: The user whose memories to search.
        query_text: The current message (or summary of recent context).
                    ChromaDB finds memories semantically similar to this.
        n_results: Max memories to return (default: settings.MEMORY_RETRIEVAL_COUNT).
        min_similarity: Minimum similarity score (default: settings.MEMORY_SIMILARITY_THRESHOLD).
                        ChromaDB returns distance scores (lower = more similar for L2,
                        but we configured cosine so higher = more similar).

    Returns:
        List of memory dicts with 'content', 'emotion_tag', 'importance', 'distance'.
        Sorted by relevance (most relevant first).
    """
    n = n_results or settings.MEMORY_RETRIEVAL_COUNT
    threshold = min_similarity or settings.MEMORY_SIMILARITY_THRESHOLD

    try:
        collection = get_chroma_collection(user_id)

        # Check if collection has anything (avoid querying empty collection)
        count = collection.count()
        if count == 0:
            return []

        # Clamp n_results to what's actually available
        actual_n = min(n, count)

        results = collection.query(
            query_texts=[query_text],
            n_results=actual_n,
            include=["documents", "metadatas", "distances"],
        )

        # ChromaDB returns nested lists (one per query_text, we only have one query)
        documents = results["documents"][0] if results["documents"] else []
        metadatas = results["metadatas"][0] if results["metadatas"] else []
        distances = results["distances"][0] if results["distances"] else []

        # Filter and format results
        memories = []
        for doc, meta, dist in zip(documents, metadatas, distances):
            # For cosine similarity: similarity = 1 - distance
            # (ChromaDB returns distance, not similarity)
            similarity = 1.0 - dist

            if similarity < threshold:
                continue

            memories.append({
                "content": doc,
                "emotion_tag": meta.get("emotion_tag", ""),
                "importance": float(meta.get("importance", 0.5)),
                "similarity": round(similarity, 3),
            })

        # Sort: most important + most similar first
        # Blend: 60% importance, 40% similarity
        memories.sort(
            key=lambda m: (m["importance"] * 0.6) + (m["similarity"] * 0.4),
            reverse=True,
        )

        logger.debug(
            f"Retrieved {len(memories)}/{actual_n} memories for user {user_id} "
            f"(query: '{query_text[:50]}...')"
        )
        return memories

    except Exception as e:
        # Memory retrieval failure should NEVER break the chat
        logger.error(f"Memory retrieval failed for user {user_id}: {e}", exc_info=True)
        return []


# ---------------------------------------------------------------------------
# Memory management utilities
# ---------------------------------------------------------------------------

def get_memory_count(user_id: str) -> int:
    """Returns how many memories are stored for a user."""
    try:
        collection = get_chroma_collection(user_id)
        return collection.count()
    except Exception:
        return 0


def delete_memory(user_id: str, memory_id: str) -> bool:
    """
    Deletes a specific memory by ID.
    Future feature: let users remove memories they don't want Nova to keep.
    """
    try:
        collection = get_chroma_collection(user_id)
        collection.delete(ids=[memory_id])
        return True
    except Exception as e:
        logger.error(f"Failed to delete memory {memory_id}: {e}")
        return False


def clear_all_memories(user_id: str) -> bool:
    """
    Deletes ALL memories for a user.
    Future feature: "forget everything" option for user privacy control.
    """
    try:
        client = get_chroma_client()
        collection_name = _sanitize_collection_name(f"user_{user_id}")
        client.delete_collection(collection_name)
        logger.info(f"Cleared all memories for user {user_id}")
        return True
    except Exception as e:
        logger.error(f"Failed to clear memories for user {user_id}: {e}")
        return False


def format_memories_for_prompt(memories: list[dict]) -> str:
    """
    Formats retrieved memories into a clean block for the LLM prompt.
    This is what context_builder.py calls to turn memory objects into text.

    Output example:
        [Memory: User's dog Mango died last year. They still miss her deeply.]
        [Memory: User is anxious about a job interview next Monday at Google.]
    """
    if not memories:
        return ""

    lines = []
    for mem in memories:
        emotion = f" ({mem['emotion_tag']})" if mem.get("emotion_tag") else ""
        lines.append(f"[Memory{emotion}: {mem['content']}]")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _sanitize_collection_name(name: str) -> str:
    """
    ChromaDB collection names must be 3-63 chars, alphanumeric + hyphens.
    UUIDs have dashes which are fine. We just need to replace underscores
    and ensure length compliance.
    """
    sanitized = name.replace("_", "-").lower()
    # Truncate if somehow too long (UUID-based IDs won't be)
    return sanitized[:63]