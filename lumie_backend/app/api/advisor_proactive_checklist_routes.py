"""Advisor proactive checklist routes.

Manage user-defined proactive manual checklist items used by proactive mode.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..core.database import get_database
from ..core.datetime_utils import format_utc_datetime
from ..services.auth_service import get_current_user_id

router = APIRouter(prefix="/advisor/proactive-checklist", tags=["advisor"])


class ProactiveChecklistItem(BaseModel):
    item_id: str
    text: str
    created_at: str
    updated_at: str


class ProactiveChecklistResponse(BaseModel):
    manual_items: list[ProactiveChecklistItem] = []
    updated_at: Optional[str] = None


class ProactiveChecklistReplaceRequest(BaseModel):
    manual_items: list[str] = Field(default_factory=list, max_length=20)


class ProactiveChecklistCreateItemRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=240)


class ProactiveChecklistUpdateItemRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=240)


def _normalize_manual_items(raw_items: list) -> list[dict]:
    now_str = format_utc_datetime(datetime.now(timezone.utc))
    normalized: list[dict] = []
    seen = set()
    for raw in raw_items:
        if isinstance(raw, str):
            text = raw.strip()
            if not text:
                continue
            dedupe_key = text.lower()
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            normalized.append({
                "item_id": str(uuid.uuid4()),
                "text": text,
                "created_at": now_str,
                "updated_at": now_str,
            })
        elif isinstance(raw, dict):
            text = str(raw.get("text", "")).strip()
            if not text:
                continue
            dedupe_key = text.lower()
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)
            normalized_item = {
                "item_id": str(raw.get("item_id") or uuid.uuid4()),
                "text": text,
                "created_at": str(raw.get("created_at") or now_str),
                "updated_at": str(raw.get("updated_at") or now_str),
            }
            # Preserve proactive execution metadata when present.
            for k in ("status", "last_run_at", "last_result", "retry_count"):
                if k in raw:
                    normalized_item[k] = raw.get(k)
            normalized.append(normalized_item)
    return normalized[:20]


async def _get_doc(db, user_id: str) -> dict:
    doc = await db.proactive_checklists.find_one({"user_id": user_id}, {"_id": 0})
    if not doc:
        return {"user_id": user_id, "manual_items": [], "updated_at": None}

    manual_items = _normalize_manual_items(doc.get("manual_items") or [])
    if manual_items != (doc.get("manual_items") or []):
        # Lightweight migration for any legacy string-only items.
        now_str = format_utc_datetime(datetime.now(timezone.utc))
        await db.proactive_checklists.update_one(
            {"user_id": user_id},
            {"$set": {"manual_items": manual_items, "updated_at": now_str}},
        )
        doc["updated_at"] = now_str
    doc["manual_items"] = manual_items
    return doc


@router.get("", response_model=ProactiveChecklistResponse)
async def get_proactive_checklist(
    user_id: str = Depends(get_current_user_id),
):
    db = get_database()
    doc = await _get_doc(db, user_id)
    return ProactiveChecklistResponse(
        manual_items=[ProactiveChecklistItem(**i) for i in doc.get("manual_items", [])],
        updated_at=doc.get("updated_at"),
    )


@router.put("", response_model=ProactiveChecklistResponse)
async def replace_proactive_checklist(
    body: ProactiveChecklistReplaceRequest,
    user_id: str = Depends(get_current_user_id),
):
    db = get_database()
    now_str = format_utc_datetime(datetime.now(timezone.utc))
    normalized = _normalize_manual_items(body.manual_items)
    await db.proactive_checklists.update_one(
        {"user_id": user_id},
        {"$set": {"manual_items": normalized, "updated_at": now_str, "user_id": user_id}},
        upsert=True,
    )
    return ProactiveChecklistResponse(
        manual_items=[ProactiveChecklistItem(**i) for i in normalized],
        updated_at=now_str,
    )


@router.post("/items", response_model=ProactiveChecklistResponse)
async def create_proactive_checklist_item(
    body: ProactiveChecklistCreateItemRequest,
    user_id: str = Depends(get_current_user_id),
):
    db = get_database()
    doc = await _get_doc(db, user_id)
    manual_items = doc.get("manual_items", [])
    if len(manual_items) >= 20:
        raise HTTPException(status_code=400, detail="Checklist limit reached (max 20 items).")

    text = body.text.strip()
    if any((i.get("text", "").strip().lower() == text.lower()) for i in manual_items):
        raise HTTPException(status_code=409, detail="Checklist item already exists.")

    now_str = format_utc_datetime(datetime.now(timezone.utc))
    manual_items.append({
        "item_id": str(uuid.uuid4()),
        "text": text,
        "created_at": now_str,
        "updated_at": now_str,
    })

    await db.proactive_checklists.update_one(
        {"user_id": user_id},
        {"$set": {"manual_items": manual_items, "updated_at": now_str, "user_id": user_id}},
        upsert=True,
    )
    return ProactiveChecklistResponse(
        manual_items=[ProactiveChecklistItem(**i) for i in manual_items],
        updated_at=now_str,
    )


@router.patch("/items/{item_id}", response_model=ProactiveChecklistResponse)
async def update_proactive_checklist_item(
    item_id: str,
    body: ProactiveChecklistUpdateItemRequest,
    user_id: str = Depends(get_current_user_id),
):
    db = get_database()
    doc = await _get_doc(db, user_id)
    manual_items = doc.get("manual_items", [])

    now_str = format_utc_datetime(datetime.now(timezone.utc))
    updated = False
    new_text = body.text.strip()

    for item in manual_items:
        if item.get("item_id") == item_id:
            item["text"] = new_text
            item["updated_at"] = now_str
            updated = True
            break

    if not updated:
        raise HTTPException(status_code=404, detail="Checklist item not found.")

    deduped = _normalize_manual_items(manual_items)
    await db.proactive_checklists.update_one(
        {"user_id": user_id},
        {"$set": {"manual_items": deduped, "updated_at": now_str, "user_id": user_id}},
        upsert=True,
    )
    return ProactiveChecklistResponse(
        manual_items=[ProactiveChecklistItem(**i) for i in deduped],
        updated_at=now_str,
    )


@router.delete("/items/{item_id}", response_model=ProactiveChecklistResponse)
async def delete_proactive_checklist_item(
    item_id: str,
    user_id: str = Depends(get_current_user_id),
):
    db = get_database()
    doc = await _get_doc(db, user_id)
    manual_items = doc.get("manual_items", [])
    filtered = [i for i in manual_items if i.get("item_id") != item_id]

    if len(filtered) == len(manual_items):
        raise HTTPException(status_code=404, detail="Checklist item not found.")

    now_str = format_utc_datetime(datetime.now(timezone.utc))
    await db.proactive_checklists.update_one(
        {"user_id": user_id},
        {"$set": {"manual_items": filtered, "updated_at": now_str, "user_id": user_id}},
        upsert=True,
    )
    return ProactiveChecklistResponse(
        manual_items=[ProactiveChecklistItem(**i) for i in filtered],
        updated_at=now_str,
    )
