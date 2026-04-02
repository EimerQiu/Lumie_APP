"""Proactive Skill Selector — chooses which assessment skills to run.

Uses the skill registry's proactive metadata to select skills based on
enabled capabilities, domain, and priority.
"""
import logging
from .skill_registry_service import skill_registry, SkillIndexItem

logger = logging.getLogger(__name__)


def select_proactive_skills(enabled_capabilities: set[str]) -> list[SkillIndexItem]:
    """Select proactive assessment skills for a run.

    Selection rules:
    - Only proactive_eligible = true
    - Must have a compatible capability
    - One assessment skill per domain (highest priority wins)
    - Sorted by priority descending

    Returns:
        Ordered list of SkillIndexItem to run.
    """
    candidates = skill_registry.get_proactive_skills_for_capabilities(enabled_capabilities)

    if not candidates:
        logger.info("ProactiveSelector: no proactive-eligible skills for capabilities %s", enabled_capabilities)
        return []

    # Deduplicate: one per domain, highest priority wins
    by_domain: dict[str, SkillIndexItem] = {}
    for skill in candidates:
        domain = skill.proactive_domain or "unknown"
        if skill.proactive_mode != "assessment":
            continue
        if domain not in by_domain or skill.proactive_priority > by_domain[domain].proactive_priority:
            by_domain[domain] = skill

    selected = sorted(by_domain.values(), key=lambda s: s.proactive_priority, reverse=True)

    logger.info(
        "ProactiveSelector: selected %d skills: %s",
        len(selected),
        [(s.skill_id, s.proactive_domain, s.proactive_priority) for s in selected],
    )
    return selected
