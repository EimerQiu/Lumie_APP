"""Proactive Guardrails — deterministic pre-LLM decision rules.

These guardrails short-circuit the LLM call for obvious cases,
reducing latency and cost while improving determinism.
"""
import hashlib
import json
import logging
from datetime import datetime, timezone

from ..models.proactive import GuardrailVerdict, ProactiveSkillResult, ProactiveStatus

logger = logging.getLogger(__name__)

# Minimum minutes between nudges (unless hard nudge)
COOLDOWN_MINUTES = 90

# Score thresholds
NO_CONCERN_THRESHOLD = 0.15
FORCE_NUDGE_THRESHOLD = 0.85
LOW_PRIORITY_DOMAINS = {"dayprint", "team_followup"}
LOW_PRIORITY_FORCE_THRESHOLD = 0.30
NO_CHANGE_STREAK_THRESHOLD = 2
LOW_PRIORITY_NUDGE_COOLDOWN_MINUTES = 24 * 60


def compute_decision_inputs_hash(skill_results: list[ProactiveSkillResult]) -> str:
    """Compute a deterministic hash of the skill results for material change detection.

    Uses domain + status + score (rounded) + sorted signals as hash input.
    Two runs with materially similar results will produce the same hash.
    """
    hashable = []
    for r in sorted(skill_results, key=lambda x: x.domain):
        hashable.append({
            "domain": r.domain,
            "status": r.status.value,
            "score_bucket": round(r.score, 1),  # bucket to 0.1 to absorb minor fluctuations
            "signals": sorted(r.signals),
        })
    raw = json.dumps(hashable, sort_keys=True)
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def build_evidence_summary(skill_results: list[ProactiveSkillResult]) -> dict:
    """Build a compact evidence summary from skill results.

    Returns: {domain: {score, status, top_signal}}
    """
    summary = {}
    for r in skill_results:
        summary[r.domain] = {
            "score": r.score,
            "status": r.status.value,
            "top_signal": r.signals[0] if r.signals else None,
        }
    return summary


def evaluate(
    skill_results: list[ProactiveSkillResult],
    last_nudge: dict | None,
    now_utc: datetime,
    no_material_change_streak: int = 0,
) -> GuardrailVerdict:
    """Evaluate deterministic guardrails before calling the LLM.

    Rules applied in order:
    1. All insufficient data / missing → skip
    2. No concerns (all scores < 0.15) → skip
    3. Cooldown (last nudge < 90 min ago, unless hard nudge) → skip
    4. No material change (same decision_inputs_hash as last nudge) → skip,
       unless stale-streak fallback promotes low-priority follow-up
    5. Hard nudge (any score >= 0.85) → force
    6. Otherwise → proceed to LLM
    """
    if not skill_results:
        return GuardrailVerdict(
            action="skip_nudge",
            reason="no_assessment_results",
        )

    # 1. All insufficient / missing
    if all(r.status in (ProactiveStatus.INSUFFICIENT_DATA, ProactiveStatus.MISSING)
           for r in skill_results):
        return GuardrailVerdict(
            action="skip_nudge",
            reason="all_insufficient_data",
            details={"statuses": [r.status.value for r in skill_results]},
        )

    max_score = max(r.score for r in skill_results)
    top_result = max(skill_results, key=lambda r: r.score)

    # 2. No concerns
    if max_score < NO_CONCERN_THRESHOLD:
        return GuardrailVerdict(
            action="skip_nudge",
            reason="no_concerns",
            details={"max_score": max_score},
        )

    # 3. Cooldown check
    if last_nudge and max_score < FORCE_NUDGE_THRESHOLD:
        nudged_at_raw = last_nudge.get("nudged_at", "")
        try:
            nudged_at_dt = datetime.fromisoformat(nudged_at_raw)
            if nudged_at_dt.tzinfo is None:
                nudged_at_dt = nudged_at_dt.replace(tzinfo=timezone.utc)
            minutes_since = (now_utc - nudged_at_dt).total_seconds() / 60
            if minutes_since < COOLDOWN_MINUTES:
                return GuardrailVerdict(
                    action="skip_nudge",
                    reason=f"cooldown_{minutes_since:.0f}min_since_last",
                    details={
                        "minutes_since_last": round(minutes_since, 1),
                        "cooldown_minutes": COOLDOWN_MINUTES,
                        "last_reason": last_nudge.get("reason", ""),
                    },
                )
        except (ValueError, TypeError):
            pass

    # 4. No material change — same structured hash as last nudge
    if last_nudge:
        last_hash = last_nudge.get("decision_inputs_hash")
        if last_hash:
            current_hash = compute_decision_inputs_hash(skill_results)
            if current_hash == last_hash:
                low_priority_candidates = sorted(
                    [
                        r for r in skill_results
                        if r.domain in LOW_PRIORITY_DOMAINS and r.score >= LOW_PRIORITY_FORCE_THRESHOLD
                    ],
                    key=lambda x: x.score,
                    reverse=True,
                )

                if no_material_change_streak >= NO_CHANGE_STREAK_THRESHOLD and low_priority_candidates:
                    minutes_since_last = None
                    try:
                        nudged_at_raw = last_nudge.get("nudged_at", "")
                        nudged_at_dt = datetime.fromisoformat(nudged_at_raw)
                        if nudged_at_dt.tzinfo is None:
                            nudged_at_dt = nudged_at_dt.replace(tzinfo=timezone.utc)
                        minutes_since_last = (now_utc - nudged_at_dt).total_seconds() / 60
                    except (ValueError, TypeError):
                        pass

                    blocked_domains: list[str] = []
                    for target in low_priority_candidates:
                        blocked_by_same_domain_cooldown = (
                            (last_nudge.get("primary_domain") == target.domain)
                            and (minutes_since_last is not None)
                            and (minutes_since_last < LOW_PRIORITY_NUDGE_COOLDOWN_MINUTES)
                        )
                        if blocked_by_same_domain_cooldown:
                            blocked_domains.append(target.domain)
                            continue

                        return GuardrailVerdict(
                            action="force_nudge",
                            reason=f"stale_high_priority_shift_to_{target.domain}",
                            details={
                                "target_domain": target.domain,
                                "target_score": target.score,
                                "target_signals": target.signals,
                                "no_material_change_streak": no_material_change_streak,
                                "decision_inputs_hash": current_hash,
                            },
                        )

                    return GuardrailVerdict(
                        action="skip_nudge",
                        reason="low_priority_followup_cooldown",
                        details={
                            "blocked_domains": blocked_domains,
                            "no_material_change_streak": no_material_change_streak,
                            "minutes_since_last": round(minutes_since_last, 1) if minutes_since_last is not None else None,
                            "cooldown_minutes": LOW_PRIORITY_NUDGE_COOLDOWN_MINUTES,
                        },
                    )

                return GuardrailVerdict(
                    action="skip_nudge",
                    reason="no_material_change",
                    details={
                        "decision_inputs_hash": current_hash,
                        "last_reason": last_nudge.get("reason", ""),
                        "no_material_change_streak": no_material_change_streak,
                    },
                )

    # 5. Hard nudge — severe concern
    if max_score >= FORCE_NUDGE_THRESHOLD:
        return GuardrailVerdict(
            action="force_nudge",
            reason=f"severe_{top_result.domain}_concern",
            details={
                "domain": top_result.domain,
                "score": top_result.score,
                "signals": top_result.signals,
            },
        )

    # 6. Proceed to LLM
    return GuardrailVerdict(
        action="proceed_to_llm",
        reason="assessments_warrant_llm_decision",
        details={"max_score": max_score, "top_domain": top_result.domain},
    )
