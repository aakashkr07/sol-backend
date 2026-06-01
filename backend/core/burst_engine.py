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
    relationship_state: Optional[dict] = None,
) -> BurstPlan:
    text = _normalize_text(raw_text)
    if not text:
        text = "..."

    segments = _split_into_bursts(text)
    if len(segments) == 1:
        segments = _heuristic_split(segments[0], character, relationship_state)
    segments = _collapse_small_bursts([segment for segment in segments if segment], character, relationship_state)
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
                    character=character,
                    relationship_state=relationship_state,
                ),
                typing_duration_ms=_typing_duration_for_segment(
                    segment=segment,
                    pause_intensity=pause_intensity,
                    is_follow_up=is_follow_up,
                    character=character,
                    relationship_state=relationship_state,
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


def _heuristic_split(text: str, character: Character, relationship_state: Optional[dict] = None) -> list[str]:
    text = _clean_segment(text)
    if not text:
        return []

    mp = character.matching_profile or {}
    rhythm = mp.get("rhythm", "steady")
    closeness = float(relationship_state.get("closeness_score") or 0.18) if relationship_state else 0.18

    if rhythm == "burst":
        sentences = _split_sentences(text)
        if len(sentences) >= 2:
            grouped = _group_sentences(sentences, character, relationship_state)
            if len(grouped) > 1:
                return grouped[:MAX_BURSTS]

        if len(text) <= 50:
            return [text]

        clause_split = _split_on_soft_connectors(text, rhythm="burst")
        if len(clause_split) > 1:
            return clause_split[:MAX_BURSTS]
    else:
        # Steady rhythm: keep as a single clean paragraph, but allow slight relaxation (more splits) as they get close
        target_len = max(110, int(180 - (closeness * 70)))
        if len(text) <= target_len:
            return [text]

        sentences = _split_sentences(text)
        if len(sentences) >= 2:
            grouped = _group_sentences(sentences, character, relationship_state)
            if len(grouped) > 1:
                return grouped[:MAX_BURSTS]

        clause_split = _split_on_soft_connectors(text, rhythm="steady")
        if len(clause_split) > 1:
            return clause_split[:MAX_BURSTS]

    return [text]


def _split_sentences(text: str) -> list[str]:
    chunks = re.split(r"(?<=[.!?…])\s+", text)
    return [_clean_segment(chunk) for chunk in chunks if _clean_segment(chunk)]


def _group_sentences(sentences: list[str], character: Character, relationship_state: Optional[dict] = None) -> list[str]:
    mp = character.matching_profile or {}
    rhythm = mp.get("rhythm", "steady")
    closeness = float(relationship_state.get("closeness_score") or 0.18) if relationship_state else 0.18

    if rhythm == "burst":
        target_chars = 38
    else:
        # Steady character targets ~160 chars, scaling down to 90 as intimacy/closeness grows
        target_chars = max(90, int(160 - (closeness * 70)))

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


def _split_on_soft_connectors(text: str, rhythm: str = "steady") -> list[str]:
    if rhythm == "steady" and len(text) < 130:
        return [text]

    parts = re.split(r"\s+(?=(?:but|and|so|because|also|wait|okay|ok|plus)\b)", text, maxsplit=2, flags=re.IGNORECASE)
    cleaned = [_clean_segment(part) for part in parts if _clean_segment(part)]
    if len(cleaned) == 1:
        midpoint = max(24, len(text) // 2)
        left = _clean_segment(text[:midpoint])
        right = _clean_segment(text[midpoint:])
        if left and right and len(left) >= 18 and len(right) >= 12:
            return [left, right]
    return cleaned


def _collapse_small_bursts(segments: list[str], character: Character, relationship_state: Optional[dict] = None) -> list[str]:
    if len(segments) <= 1:
        return segments

    mp = character.matching_profile or {}
    rhythm = mp.get("rhythm", "steady")
    
    # Burst characters allow smaller chunks
    min_len = 8 if rhythm == "burst" else 22

    collapsed: list[str] = []
    for segment in segments:
        if collapsed and (len(segment) < min_len or len(segment.split()) <= 2) and not _looks_like_standalone_ping(segment):
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
    character: Character,
    relationship_state: Optional[dict] = None,
) -> int:
    trust = float(relationship_state.get("trust_score") or 0.18) if relationship_state else 0.18
    comfort = float(relationship_state.get("comfort_score") or 0.14) if relationship_state else 0.14
    
    mp = character.matching_profile or {}
    pace = mp.get("response_pace", "measured")
    rhythm = mp.get("rhythm", "steady")
    traits = character.personality_traits or {}
    flaws = [f.lower() for f in traits.get("flaws", [])]
    flaws_str = " ".join(flaws)
    
    if index == 0:
        # Base latency for first response
        if pace == "fast":
            base = 150
        elif pace == "slow":
            # Slow paced character: starts at ~4000ms delay, but scales down as comfort progresses to 1.0!
            base = int(900 + 3100 * (1.0 - comfort))
        else:
            # Measured pacing: 700ms base, scales down slightly to 400ms.
            base = int(400 + 300 * (1.0 - comfort))
            
        # Add reading duration based on user message length
        read_factor = 3 if pace == "slow" else 1 if pace == "fast" else 2
        base += min(400, len(user_message) * read_factor)
        
        if is_opening:
            base += 200
            
        # Flaw-driven Modifiers:
        # AVOIDANT / GUARDED:
        # Hesitates when faced with user vulnerability. Detect emotional words in user message.
        is_user_vulnerable = any(w in user_message.lower() for w in ["feel", "sad", "hurt", "scared", "lonely", "miss", "sorry", "cry", "upset", "pain"])
        openness_level = mp.get("openness_level", "warm")
        is_avoidant = (openness_level == "guarded") or any(
            w in flaws_str or w in (character.archetype or "").lower() or w in (character.summary or "").lower()
            for w in ["avoidant", "guarded", "reserved", "defensive", "silent", "distant"]
        )
        if is_user_vulnerable and is_avoidant:
            # Hesitation bonus up to 4.5 seconds when trust is low, scales down to 0 as trust grows to 1.0
            hesitation_bonus = int(4500 * (1.0 - trust))
            base += hesitation_bonus
            
        # CLINGY / IMPULSIVE:
        # Responds extremely fast (cut base delay by up to 45%)
        is_clingy = "clingy" in flaws_str or "impulsive" in flaws_str
        if is_clingy:
            base = int(base * 0.55)
            
        # OVERTHINKS CONSTANTLY:
        # Hesitates slightly before sending the first message
        if "overthink" in flaws_str or "anxious" in flaws_str:
            base += int(1200 * (1.0 - comfort))
    else:
        # Latency between consecutive split messages
        if rhythm == "burst":
            base = 120
        else:
            base = 250
            
    # Bonuses based on pause intensity
    intensity_bonus = {
        "brief": 80,
        "medium": 240,
        "long": 700,
    }[pause_intensity]
    
    # Length & trailing character bonuses
    length_bonus = min(300, len(segment) * (4 if pace == "slow" else 2))
    punctuation_bonus = 180 if segment.endswith("...") else 100 if segment.endswith("?") else 0
    follow_up_bonus = 300 if is_follow_up else 0
    
    total_delay = base + intensity_bonus + length_bonus + punctuation_bonus + follow_up_bonus
    
    # Clamping range
    max_clamp = 10000 if pace == "slow" else 5000
    min_clamp = 100 if pace == "fast" else 160
    
    return max(min_clamp, min(total_delay, max_clamp))


def _typing_duration_for_segment(
    segment: str,
    pause_intensity: str,
    is_follow_up: bool,
    character: Character,
    relationship_state: Optional[dict] = None,
) -> int:
    comfort = float(relationship_state.get("comfort_score") or 0.14) if relationship_state else 0.14

    mp = character.matching_profile or {}
    pace = mp.get("response_pace", "measured")
    traits = character.personality_traits or {}
    flaws = [f.lower() for f in traits.get("flaws", [])]
    flaws_str = " ".join(flaws)

    chars_multiplier = 14 if pace == "slow" else 6 if pace == "fast" else 9
    base = 400 + min(800, len(segment) * chars_multiplier)

    # Flaw-driven Modifiers:
    # OVERTHINKS CONSTANTLY:
    # Simulates typing, pausing, deleting, re-typing! Adds a huge typing duration.
    is_overthinking = any(
        w in flaws_str or w in (character.archetype or "").lower() or w in (character.summary or "").lower()
        for w in ["overthink", "anxious", "perfectionist", "worry", "hesitat"]
    )
    if is_overthinking:
        overthink_pause = int(400 + 1400 * (1.0 - comfort))
        base += overthink_pause

    # CLINGY / IMPULSIVE:
    # Types extremely fast
    if "clingy" in flaws_str or "impulsive" in flaws_str:
        base = int(base * 0.75)

    modifier = {
        "brief": -80,
        "medium": 60,
        "long": 200,
    }[pause_intensity]
    if is_follow_up:
        modifier += 150

    total_typing = base + modifier
    
    # Clamping range
    max_clamp = 4000 if "overthink" in flaws_str else 2500
    min_clamp = 250 if pace == "fast" else 350
    
    return max(min_clamp, min(total_typing, max_clamp))


def _looks_like_standalone_ping(segment: str) -> bool:
    lowered = re.sub(r"[^\w\s]", "", segment.lower().strip())
    return lowered in {
        "wait",
        "okay wait",
        "hold on",
        "hang on",
        "okay but",
        "no because",
        "right",
        "nah",
        "okay hold on",
        "hold on a sec",
        "wait what",
    }


def _clean_segment(segment: str) -> str:
    cleaned = re.sub(r"\s+", " ", segment.replace(EXPLICIT_BURST_TOKEN, " ")).strip()
    return cleaned
