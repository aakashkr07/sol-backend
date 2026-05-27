import re
from dataclasses import dataclass
from typing import Optional

from personality.loader import Character

MAX_BURSTS = 4
EXPLICIT_BURST_TOKEN = "[BURST]"


@dataclass(frozen=True)
class BurstSegment:
    text: str
    pre_burst_delay_ms: int
    typing_duration_ms: int
    pause_intensity: str
    is_follow_up: bool = False


@dataclass(frozen=True)
class BurstPlan:
    combined_text: str
    bursts: list[BurstSegment]


def plan_burst_response(
    raw_text: str,
    character: Character,
    user_message: Optional[str] = None,
    is_opening: bool = False,
) -> BurstPlan:
    text = _normalize_text(raw_text)
    if not text:
        text = "..."

    segments = _split_into_bursts(text)
    if len(segments) == 1:
        segments = _heuristic_split(segments[0], character)
    segments = _collapse_small_bursts([segment for segment in segments if segment], character)
    if not segments:
        segments = [text]

    follow_up_index = _detect_follow_up_index(segments)
    bursts = []
    for index, segment in enumerate(segments):
        is_follow_up = follow_up_index == index
        pause_intensity = _pause_intensity_for_segment(
            segment=segment,
            index=index,
            total=len(segments),
            is_opening=is_opening,
            is_follow_up=is_follow_up,
        )
        bursts.append(
            BurstSegment(
                text=segment,
                pre_burst_delay_ms=_delay_for_segment(
                    segment=segment,
                    index=index,
                    total=len(segments),
                    user_message=user_message or "",
                    pause_intensity=pause_intensity,
                    is_opening=is_opening,
                    is_follow_up=is_follow_up,
                ),
                typing_duration_ms=_typing_duration_for_segment(
                    segment=segment,
                    pause_intensity=pause_intensity,
                    is_follow_up=is_follow_up,
                ),
                pause_intensity=pause_intensity,
                is_follow_up=is_follow_up,
            )
        )

    return BurstPlan(
        combined_text="\n".join(segment.text for segment in bursts),
        bursts=bursts,
    )


def _normalize_text(raw_text: str) -> str:
    text = (raw_text or "").replace("\r\n", "\n").strip()
    text = re.sub(r"\s*\[burst\]\s*", f" {EXPLICIT_BURST_TOKEN} ", text, flags=re.IGNORECASE)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _split_into_bursts(text: str) -> list[str]:
    if EXPLICIT_BURST_TOKEN in text:
        return [_clean_segment(part) for part in text.split(EXPLICIT_BURST_TOKEN)]

    if "\n\n" in text:
        return [_clean_segment(part) for part in text.split("\n\n")]

    if "\n" in text:
        return [_clean_segment(part) for part in text.split("\n")]

    return [_clean_segment(text)]


def _heuristic_split(text: str, character: Character) -> list[str]:
    text = _clean_segment(text)
    if not text:
        return []

    sentences = _split_sentences(text)
    if len(sentences) >= 2:
        grouped = _group_sentences(sentences, character)
        if len(grouped) > 1:
            return grouped[:MAX_BURSTS]

    if len(text) <= 95:
        return [text]

    clause_split = _split_on_soft_connectors(text)
    if len(clause_split) > 1:
        return clause_split[:MAX_BURSTS]

    return [text]


def _split_sentences(text: str) -> list[str]:
    chunks = re.split(r"(?<=[.!?…])\s+", text)
    return [_clean_segment(chunk) for chunk in chunks if _clean_segment(chunk)]


def _group_sentences(sentences: list[str], character: Character) -> list[str]:
    style = character.texting_style or {}
    prefers_bursts = "burst" in str(style.get("message_length", {}).get("default", "")).lower()
    target_chars = 46 if prefers_bursts else 68
    groups: list[str] = []
    current = ""

    for sentence in sentences:
        candidate = sentence if not current else f"{current} {sentence}"
        should_break = (
            current
            and (
                len(candidate) > target_chars
                or len(groups) >= MAX_BURSTS - 1
                or _looks_like_standalone_ping(sentence)
            )
        )
        if should_break:
            groups.append(current)
            current = sentence
        else:
            current = candidate

    if current:
        groups.append(current)
    return [_clean_segment(group) for group in groups if _clean_segment(group)]


def _split_on_soft_connectors(text: str) -> list[str]:
    parts = re.split(r"\s+(?=(?:but|and|so|because|also|wait|okay|ok|plus)\b)", text, maxsplit=2, flags=re.IGNORECASE)
    cleaned = [_clean_segment(part) for part in parts if _clean_segment(part)]
    if len(cleaned) == 1:
        midpoint = max(24, len(text) // 2)
        left = _clean_segment(text[:midpoint])
        right = _clean_segment(text[midpoint:])
        if left and right and len(left) >= 18 and len(right) >= 12:
            return [left, right]
    return cleaned


def _collapse_small_bursts(segments: list[str], character: Character) -> list[str]:
    if len(segments) <= 1:
        return segments

    collapsed: list[str] = []
    for segment in segments:
        if collapsed and (len(segment) < 8 or len(segment.split()) == 1) and not _looks_like_standalone_ping(segment):
            collapsed[-1] = f"{collapsed[-1]} {segment}".strip()
        else:
            collapsed.append(segment)

    while len(collapsed) > MAX_BURSTS:
        collapsed[-2] = f"{collapsed[-2]} {collapsed[-1]}".strip()
        collapsed.pop()

    return collapsed


def _detect_follow_up_index(segments: list[str]) -> Optional[int]:
    if len(segments) < 2:
        return None

    last = segments[-1]
    if len(last) <= 42 or len(last.split()) <= 7:
        return len(segments) - 1

    return None


def _pause_intensity_for_segment(
    segment: str,
    index: int,
    total: int,
    is_opening: bool,
    is_follow_up: bool,
) -> str:
    if is_follow_up:
        return "long"
    if index == 0 and is_opening:
        return "medium"
    if total == 1:
        return "medium" if len(segment) > 100 or segment.endswith("...") else "brief"
    if segment.endswith("..."):
        return "medium"
    if _looks_like_standalone_ping(segment):
        return "brief"
    if index == total - 1 and segment.endswith("?"):
        return "medium"
    return "brief"


def _delay_for_segment(
    segment: str,
    index: int,
    total: int,
    user_message: str,
    pause_intensity: str,
    is_opening: bool,
    is_follow_up: bool,
) -> int:
    base = 320 if index == 0 else 180
    if index == 0:
        base += min(260, len(user_message) * 2)
        if is_opening:
            base += 180

    intensity_bonus = {
        "brief": 90,
        "medium": 260,
        "long": 820,
    }[pause_intensity]

    length_bonus = min(240, len(segment) * 3)
    punctuation_bonus = 160 if segment.endswith("...") else 90 if segment.endswith("?") else 0
    follow_up_bonus = 320 if is_follow_up else 0
    total_delay = base + intensity_bonus + length_bonus + punctuation_bonus + follow_up_bonus
    return max(160, min(total_delay, 2600))


def _typing_duration_for_segment(
    segment: str,
    pause_intensity: str,
    is_follow_up: bool,
) -> int:
    base = 460 + min(540, len(segment) * 8)
    modifier = {
        "brief": -90,
        "medium": 50,
        "long": 180,
    }[pause_intensity]
    if is_follow_up:
        modifier += 140
    return max(320, min(base + modifier, 1800))


def _looks_like_standalone_ping(segment: str) -> bool:
    lowered = segment.lower().strip()
    return lowered in {
        "wait",
        "okay wait",
        "hold on",
        "hang on",
        "okay but",
        "no because",
        "right",
    }


def _clean_segment(segment: str) -> str:
    cleaned = re.sub(r"\s+", " ", segment.replace(EXPLICIT_BURST_TOKEN, " ")).strip()
    return cleaned
