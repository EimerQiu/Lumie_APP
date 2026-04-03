"""Proactive assessment skill modules.

Each module exposes an `assess(db, user_id, now_utc)` coroutine
that returns a ProactiveSkillResult.
"""
from .sleep_assessment import assess as assess_sleep
from .activity_assessment import assess as assess_activity
from .medication_assessment import assess as assess_medication
from .recovery_assessment import assess as assess_recovery
from .dayprint_followup_assessment import assess as assess_dayprint_followup
from .team_member_followup_assessment import assess as assess_team_followup

ALL_ASSESSMENTS = [
    assess_sleep,
    assess_activity,
    assess_medication,
    assess_recovery,
    assess_dayprint_followup,
    assess_team_followup,
]

DOMAIN_ASSESSMENTS = {
    "sleep": assess_sleep,
    "activity": assess_activity,
    "medication": assess_medication,
    "recovery": assess_recovery,
    "dayprint": assess_dayprint_followup,
    "team_followup": assess_team_followup,
}
