"""Proactive assessment skill modules.

Each module exposes an `assess(db, user_id, now_utc)` coroutine
that returns a ProactiveSkillResult.
"""
from .sleep_assessment import assess as assess_sleep
from .activity_assessment import assess as assess_activity
from .medication_assessment import assess as assess_medication
from .recovery_assessment import assess as assess_recovery
from .dayprint_followup_assessment import assess as assess_dayprint_followup

ALL_ASSESSMENTS = [
    assess_sleep,
    assess_activity,
    assess_medication,
    assess_recovery,
    assess_dayprint_followup,
]
