"""Shared credential utilities for skill credential resolution.

Handles the mapping between skill_id and the actual DB key used to store/retrieve
credentials, accounting for shared_credential_id systems.
"""

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ..services.skill_registry_service import SkillIndexItem


def resolve_credential_key(skill: "SkillIndexItem") -> str:
    """Return the DB key used to store/retrieve a skill's credential.

    Skills with a shared_credential_id use a shared pool key
    (__shared__{id}) that is independent of any skill_id.

    Args:
        skill: The skill index item containing shared_credential_id if applicable.

    Returns:
        The credential key to use for database lookups and updates.

    Example:
        Two skills (ac_control, energy_status_query) both have shared_credential_id='home_energy':
        - resolve_credential_key(ac_control) → '__shared__home_energy'
        - resolve_credential_key(energy_status_query) → '__shared__home_energy'

        A skill with no shared_credential_id uses its own skill_id as the key:
        - resolve_credential_key(gmail_inbox_check) → 'gmail_inbox_check'
    """
    if skill.shared_credential_id:
        return f"__shared__{skill.shared_credential_id}"
    return skill.skill_id
