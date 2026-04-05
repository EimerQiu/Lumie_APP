"""Proactive Skill Selector — chooses which assessment skills to run.

Uses the skill registry's proactive metadata to select all assessment-eligible
skills. All eligible skills run in parallel, sorted by proactive_priority.
"""
import logging
from .skill_registry_service import skill_registry, SkillIndexItem

logger = logging.getLogger(__name__)


def select_proactive_skills() -> list[SkillIndexItem]:
    """Select all proactive assessment skills for a run.

    Selection rules:
    - Only proactive_eligible = true
    - Only assessment-mode skills
    - All eligible skills run in parallel (no domain-based deduplication)
    - Sorted by priority descending

    Returns:
        Ordered list of SkillIndexItem to run, sorted by priority.
    """
    candidates = skill_registry.get_proactive_skills()

    if not candidates:
        logger.info("ProactiveSelector: no proactive-eligible skills found")
        return []

    # Filter: only assessment-mode skills
    assessment_skills = [
        skill for skill in candidates
        if skill.proactive_mode == "assessment"
    ]

    # Sort by priority descending
    selected = sorted(assessment_skills, key=lambda s: s.proactive_priority, reverse=True)

    logger.info(
        "ProactiveSelector: selected %d assessment skills: %s",
        len(selected),
        [(s.skill_id, s.proactive_domain, s.proactive_priority) for s in selected],
    )
    return selected
