# =============================================================================
# core/llm.py — Groq LLM Interface
# =============================================================================
#
# PURPOSE:
#   Single interface for all LLM API calls. Every chat response goes through here.
#   Handles: Groq API calls, retry logic, rate limit fallback, response cleaning.
#
# WHY A DEDICATED FILE:
#   If you ever switch from Groq to another provider (OpenAI, Anthropic, local Ollama),
#   you change ONE file. Everything else stays the same. This is the abstraction layer.
#
# CURRENT MODEL:
#   Primary: llama-3.1-70b-versatile (best quality on Groq free tier)
#   Fallback: llama3-8b-8192 (faster, less creative but still good)
#   Free tier: ~14,400 tokens/minute. At ~300 tokens/reply, that's 48 messages/min.
#   For MVP/testing, this is more than enough.
#
# RESPONSE CLEANING:
#   LLMs sometimes add markdown formatting, quotes, or "Nova: " prefixes.
#   We strip all of that before returning — the response should be RAW TEXT only.
#
# USAGE:
#   from core.llm import generate_reply
#   reply = await generate_reply(messages=[...], system_prompt="...")
# =============================================================================

import asyncio
import logging
import re
from typing import Optional

import httpx

from config import settings
from personality.loader import list_characters, load_character

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Main generation function
# ---------------------------------------------------------------------------

async def generate_reply(
    messages: list[dict],
    system_prompt: str,
    temperature: Optional[float] = None,
    max_tokens: Optional[int] = None,
    model: Optional[str] = None,
) -> str:
    """
    Sends a request to Groq and returns the cleaned reply text.

    Args:
        messages: List of {"role": "user"|"assistant", "content": "..."} dicts.
                  This is the conversation history window (last N turns).
        system_prompt: The fully assembled system prompt from context_builder.py.
        temperature: Override default temperature (uses settings value if None).
        max_tokens: Override default max tokens.
        model: Override model (uses settings.LLM_MODEL if None).

    Returns:
        Clean reply string (no markdown, no prefix, just Nova's words).

    Raises:
        LLMError: If both primary and fallback models fail.
    """
    # Use configured defaults unless explicitly overridden
    temp = temperature if temperature is not None else settings.LLM_TEMPERATURE
    tokens = max_tokens or settings.LLM_MAX_TOKENS
    primary_model = model or settings.LLM_MODEL

    # Try primary model first, then fallback. Timeout/server stalls are common
    # enough that chat should degrade to the faster model instead of hanging.
    try:
        raw_reply = await _call_groq(
            model=primary_model,
            system_prompt=system_prompt,
            messages=messages,
            temperature=temp,
            max_tokens=tokens,
            timeout=24.0,
        )
    except Exception as primary_error:
        logger.warning(
            "Primary LLM model %s failed (%s); falling back to %s",
            primary_model,
            primary_error,
            settings.LLM_FALLBACK_MODEL,
        )
        try:
            raw_reply = await _call_groq(
                model=settings.LLM_FALLBACK_MODEL,
                system_prompt=system_prompt,
                messages=messages,
                temperature=temp,
                max_tokens=tokens,
                timeout=24.0,
            )
        except Exception as e:
            raise LLMError(f"Both models failed. Primary: {primary_error}; fallback: {e}") from e

    # Clean the response before returning
    cleaned = _clean_response(raw_reply)

    if not cleaned:
        logger.warning("LLM returned empty response after cleaning")
        return "..."    # Neutral fallback — feels more human than an error message

    return cleaned


# ---------------------------------------------------------------------------
# Groq API call
# ---------------------------------------------------------------------------

async def _call_groq(
    model: str,
    system_prompt: str,
    messages: list[dict],
    temperature: float,
    max_tokens: int,
    timeout: float = 30.0,
) -> str:
    """
    Raw Groq API call. Returns the raw content string.
    Separated from generate_reply() so we can retry with different models.
    """
    if not settings.GROQ_API_KEY:
        raise LLMError("GROQ_API_KEY not set")

    # Groq uses OpenAI-compatible format
    # System prompt goes in the "system" role, separate from messages
    payload = {
        "model": model,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": [
            {"role": "system", "content": system_prompt},
            *messages,   # Conversation history appended after system prompt
        ],
        # Stop sequences: prevent the model from generating "User:" turn continuations
        "stop": ["User:", "Human:", "\nUser:", "\nHuman:"],
    }

    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            response = await client.post(
                f"{settings.GROQ_BASE_URL}/chat/completions",
                headers={
                    "Authorization": f"Bearer {settings.GROQ_API_KEY}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )

            # Handle specific error codes
            if response.status_code == 429:
                raise RateLimitError("Groq rate limit exceeded")
            if response.status_code == 401:
                raise LLMError("Groq API key is invalid")
            if response.status_code >= 500:
                raise LLMError(f"Groq server error: {response.status_code}")

            response.raise_for_status()

            data = response.json()

            # Extract the content
            choice = data["choices"][0]
            content = choice["message"]["content"]

            # Log token usage for monitoring rate limits
            usage = data.get("usage", {})
            logger.debug(
                f"Groq [{model}]: {usage.get('prompt_tokens', '?')} prompt + "
                f"{usage.get('completion_tokens', '?')} completion tokens"
            )

            return content

        except (RateLimitError, LLMError):
            raise   # Re-raise our custom errors
        except httpx.TimeoutException:
            raise LLMError("Groq API timed out (30s)")
        except Exception as e:
            raise LLMError(f"Unexpected error calling Groq: {e}") from e


# ---------------------------------------------------------------------------
# Response cleaning
# ---------------------------------------------------------------------------

def _clean_response(text: str) -> str:
    """
    Strips artifacts that LLMs sometimes inject into their responses.
    Nova's response should be pure text — no markdown, no role labels.

    What we strip:
    - "Nova: " prefix (model sometimes echoes the role label)
    - Markdown bold/italic (**text**, *text*)
    - Markdown headers (## Header)
    - Leading/trailing quotes ("response")
    - Multiple blank lines compressed to one
    """
    if not text:
        return ""

    cleaned = text.strip()

    # Remove a leaked speaker prefix if the model echoed the role label.
    labels = "|".join(re.escape(label) for label in _known_speaker_labels())
    cleaned = re.sub(rf'^(?:{labels})\s*:\s*', '', cleaned, flags=re.IGNORECASE)

    # Remove markdown bold and italic
    cleaned = re.sub(r'\*\*(.+?)\*\*', r'\1', cleaned)  # **bold** → bold
    cleaned = re.sub(r'\*(.+?)\*', r'\1', cleaned)        # *italic* → italic

    # Remove markdown headers
    cleaned = re.sub(r'^#{1,6}\s+', '', cleaned, flags=re.MULTILINE)

    # Remove markdown bullet points (shouldn't appear, but just in case)
    cleaned = re.sub(r'^\s*[-*•]\s+', '', cleaned, flags=re.MULTILINE)

    # Strip surrounding quotes if the entire response is quoted
    if (cleaned.startswith('"') and cleaned.endswith('"')) or \
       (cleaned.startswith("'") and cleaned.endswith("'")):
        cleaned = cleaned[1:-1]

    # Collapse multiple blank lines into one
    cleaned = re.sub(r'\n{3,}', '\n\n', cleaned)

    return cleaned.strip()


def _known_speaker_labels() -> list[str]:
    labels = {"Assistant", "AI"}
    try:
        for character_id in list_characters():
            character = load_character(character_id)
            labels.add(character.id)
            labels.add(character.name)
    except Exception:
        labels.add(settings.DEFAULT_CHARACTER)
    return sorted(labels, key=len, reverse=True)


# ---------------------------------------------------------------------------
# Custom Exceptions
# ---------------------------------------------------------------------------

class LLMError(Exception):
    """Raised when the LLM call fails after all retries."""
    pass


class RateLimitError(LLMError):
    """Raised specifically when Groq returns 429 rate limit."""
    pass


# ---------------------------------------------------------------------------
# Health check utility
# ---------------------------------------------------------------------------

async def check_llm_health() -> dict:
    """
    Quick health check for the LLM connection.
    Called at startup and by the /health endpoint.
    """
    try:
        reply = await generate_reply(
            messages=[{"role": "user", "content": "say 'ok'"}],
            system_prompt="Reply with only the word 'ok'.",
            max_tokens=5,
            temperature=0.0,
        )
        return {"status": "ok", "model": settings.LLM_MODEL, "reply": reply}
    except Exception as e:
        return {"status": "error", "error": str(e)}
