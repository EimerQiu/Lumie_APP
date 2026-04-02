"""Recovery / vital signs assessment for proactive advisor."""
import logging
from datetime import datetime, timedelta

from ...models.proactive import ProactiveSkillResult, ProactiveStatus

logger = logging.getLogger(__name__)

SKILL_ID = "proactive_recovery_assessment"
DOMAIN = "recovery"


async def assess(db, user_id: str, now_utc: datetime) -> ProactiveSkillResult:
    """Assess recent vital signs (HR, HRV, temperature, SpO2)."""
    cutoff_utc = now_utc - timedelta(hours=24)

    hr_samples = await db.hr_readings.find({
        "user_id": user_id,
        "timestamp": {"$gte": cutoff_utc},
    }).sort("timestamp", -1).to_list(5)

    hrv_samples = await db.hrv_readings.find({
        "user_id": user_id,
        "timestamp": {"$gte": cutoff_utc},
    }).sort("timestamp", -1).to_list(5)

    temp_samples = await db.temperature_readings.find({
        "user_id": user_id,
        "timestamp": {"$gte": cutoff_utc},
    }).sort("timestamp", -1).to_list(5)

    spo2_samples = await db.spo2_readings.find({
        "user_id": user_id,
        "timestamp": {"$gte": cutoff_utc},
    }).sort("timestamp", -1).to_list(5)

    counts = {
        "hr_readings": len(hr_samples),
        "hrv_readings": len(hrv_samples),
        "temperature_readings": len(temp_samples),
        "spo2_readings": len(spo2_samples),
    }
    total_samples = sum(counts.values())

    if total_samples == 0:
        return ProactiveSkillResult(
            skill_id=SKILL_ID,
            domain=DOMAIN,
            status=ProactiveStatus.INSUFFICIENT_DATA,
            summary="No vital sign data in the last 24 hours.",
            score=0.0,
            signals=["no_recent_vitals"],
            evidence={"collections_used": list(counts.keys()), "record_counts": counts},
        )

    signals: list[str] = []
    actions: list[str] = []
    score = 0.0
    summary_parts: list[str] = []

    # Heart rate
    if hr_samples:
        latest_bpm = hr_samples[0].get("bpm")
        summary_parts.append(f"HR: {latest_bpm} bpm ({len(hr_samples)} samples)")
        if latest_bpm and latest_bpm > 110:
            score = max(score, 0.5)
            signals.append(f"elevated_hr_{latest_bpm}bpm")
        elif latest_bpm and latest_bpm > 95:
            score = max(score, 0.25)
            signals.append(f"slightly_elevated_hr_{latest_bpm}bpm")

    # HRV
    if hrv_samples:
        latest_hrv = hrv_samples[0].get("hrv_ms")
        latest_fatigue = hrv_samples[0].get("fatigue")
        parts = [f"HRV: {latest_hrv} ms"]
        if latest_fatigue is not None:
            parts.append(f"fatigue {latest_fatigue}")
        summary_parts.append(f"{', '.join(parts)} ({len(hrv_samples)} samples)")
        if latest_hrv and latest_hrv < 20:
            score = max(score, 0.5)
            signals.append(f"very_low_hrv_{latest_hrv}ms")
            actions.append("Low HRV detected — consider rest or stress management")
        elif latest_hrv and latest_hrv < 40:
            score = max(score, 0.2)
            signals.append(f"low_hrv_{latest_hrv}ms")
        if latest_fatigue and latest_fatigue > 80:
            score = max(score, 0.4)
            signals.append(f"high_fatigue_{latest_fatigue}")

    # Temperature
    if temp_samples:
        latest_temp = temp_samples[0].get("temp1_c")
        summary_parts.append(f"Temp: {latest_temp}°C ({len(temp_samples)} samples)")
        if latest_temp and latest_temp > 37.8:
            score = max(score, 0.6)
            signals.append(f"elevated_temp_{latest_temp}C")
            actions.append("Elevated temperature detected")
        elif latest_temp and latest_temp > 37.3:
            score = max(score, 0.25)
            signals.append(f"slightly_elevated_temp_{latest_temp}C")

    # SpO2
    if spo2_samples:
        latest_spo2 = spo2_samples[0].get("spo2_percent")
        summary_parts.append(f"SpO2: {latest_spo2}% ({len(spo2_samples)} samples)")
        if latest_spo2 and latest_spo2 < 92:
            score = max(score, 0.8)
            signals.append(f"low_spo2_{latest_spo2}pct")
            actions.append("Low blood oxygen — consider medical attention")
        elif latest_spo2 and latest_spo2 < 95:
            score = max(score, 0.4)
            signals.append(f"borderline_spo2_{latest_spo2}pct")

    status = ProactiveStatus.OK if score < 0.3 else ProactiveStatus.CONCERN

    # Latest timestamps for evidence
    latest_ts: dict = {}
    if hr_samples:
        ts = hr_samples[0].get("timestamp")
        latest_ts["hr"] = ts.isoformat() if isinstance(ts, datetime) else ts
    if hrv_samples:
        ts = hrv_samples[0].get("timestamp")
        latest_ts["hrv"] = ts.isoformat() if isinstance(ts, datetime) else ts
    if temp_samples:
        ts = temp_samples[0].get("timestamp")
        latest_ts["temperature"] = ts.isoformat() if isinstance(ts, datetime) else ts
    if spo2_samples:
        ts = spo2_samples[0].get("timestamp")
        latest_ts["spo2"] = ts.isoformat() if isinstance(ts, datetime) else ts

    return ProactiveSkillResult(
        skill_id=SKILL_ID,
        domain=DOMAIN,
        status=status,
        summary="; ".join(summary_parts),
        score=round(score, 2),
        signals=signals,
        recommended_actions=actions,
        evidence={
            "collections_used": list(counts.keys()),
            "record_counts": counts,
            "latest_timestamps": latest_ts,
        },
    )
