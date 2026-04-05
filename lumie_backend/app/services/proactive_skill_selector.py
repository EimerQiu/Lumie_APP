"""Proactive Skill Selector — chooses which assessment skills to run.

Uses the skill registry's proactive metadata to select skills based on
enabled capabilities and proactive_priority score.
"""
import logging
from .skill_registry_service import skill_registry, SkillIndexItem

logger = logging.getLogger(__name__)


def select_proactive_skills(enabled_capabilities: set[str]) -> list[SkillIndexItem]:
    """Select proactive assessment skills available for user's enabled capabilities.

    Selection rules:
    - Only proactive_eligible = true
    - Capability must be in enabled_capabilities
    - Only assessment-mode skills
    - Sorted by priority descending (no per-domain deduplication)

    Returns:
        Ordered list of SkillIndexItem to run, sorted by priority.
    """
    candidates = skill_registry.get_proactive_skills_for_capabilities(enabled_capabilities)

    if not candidates:
        logger.info("ProactiveSelector: no proactive-eligible skills for capabilities %s", enabled_capabilities)
        return []

    # Filter: only assessment-mode skills
    assessment_skills = [
        skill for skill in candidates
        if skill.proactive_mode == "assessment"
    ]

    # Sort by priority descending (NO per-domain deduplication)
    selected = sorted(assessment_skills, key=lambda s: s.proactive_priority, reverse=True)

    logger.info(
        "ProactiveSelector: selected %d assessment skills: %s",
        len(selected),
        [(s.skill_id, s.proactive_domain, s.proactive_priority) for s in selected],
    )
    return selected
