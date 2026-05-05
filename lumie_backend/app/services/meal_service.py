"""
Meal Service — Meal Feature business logic.

Covers (PRD §1, §5, §6, §8):
  • POST /meals/analyze — vision-based food extraction with categorical macro ratios
  • CRUD on the meal entity, including personal history and team feed
  • Correction storage for personal-bias learning
  • Bridge: completed Nutrition Task → Meal (PRD Phase-1 backward compatibility)

Design notes:
  • Macro ratios are categorical (low|moderate|high) — never numeric (PRD non-goal §3).
    Per CLAUDE.md "Use LLM API for Semantic Judgments, Not Enums", the categorization
    is performed by the LLM at analysis time using calibration anchors in the prompt,
    rather than by hardcoded gram thresholds in code.
  • Image storage mirrors the task pattern: filesystem under uploads/meals/{meal_id}/.
"""

import uuid
import shutil
import subprocess
import base64
import hashlib
import logging
import json
from io import BytesIO
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Optional, List, Any
from zoneinfo import ZoneInfo

import httpx
from fastapi import HTTPException, status, UploadFile
from pymongo.errors import DuplicateKeyError
from starlette.datastructures import Headers

from ..core.database import get_database
from ..core.config import settings
from ..core.datetime_utils import format_utc_datetime
from ..models.meal import (
    MacroLevel,
    MacroRatio,
    MealVisibility,
    MealType,
    NutritionLevel,
    FoodItem,
    MealAnalyzeResponse,
    MealCreate,
    MealUpdate,
    MealResponse,
    MealListResponse,
    MealCorrectionCreate,
    MealCorrectionResponse,
    MealTrendDay,
    MealTrendResponse,
)
from ..models.team import MemberStatus
from .dayprint_service import log_meal_logged, refresh_dayprint_event_for_meal
from .llm_client import chat_completion

logger = logging.getLogger(__name__)


# Per CLAUDE.md, calibration anchors live in one place and are referenced by every
# LLM call that needs to categorize macros (vision analyze + text bridge).
_MACRO_CALIBRATION = (
    "Calibration anchors per typical adult serving:\n"
    "  protein: low <8g, moderate 8-25g, high >25g\n"
    "  carbs:   low <15g, moderate 15-45g, high >45g\n"
    "  fat:     low <5g, moderate 5-15g, high >15g\n"
    "  fiber:   low <2g, moderate 2-5g, high >5g\n"
    "Output values for each macro must be exactly one of: 'low', 'moderate', 'high'."
)


class MealService:
    _upload_root = Path(__file__).resolve().parents[2] / "uploads" / "meals"
    _thumb_size = 320

    # ============ Image storage helpers (mirror task_service pattern) ============

    def _validate_image_upload(self, upload: UploadFile) -> str:
        """Return file extension if upload is an image; raise 400 otherwise."""
        content_type = (upload.content_type or "").lower()
        if not content_type.startswith("image/"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Only images are supported for meals: {upload.filename or 'unknown'}",
            )
        ext = Path(upload.filename or "").suffix.strip().lower()
        if not ext or len(ext) > 10:
            ext = ".jpg"
        return ext

    def _generate_thumbnail(
        self,
        source_path: Path,
        meal_id: str,
        attachment_id: str,
    ) -> tuple[Optional[str], Optional[str]]:
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            return None, None
        thumb_name = f"{attachment_id}_thumb.jpg"
        thumb_relative = f"meals/{meal_id}/{thumb_name}"
        thumb_path = self._upload_root / meal_id / thumb_name
        try:
            subprocess.run(
                [
                    ffmpeg, "-y",
                    "-i", str(source_path),
                    "-vf",
                    f"scale={self._thumb_size}:{self._thumb_size}:force_original_aspect_ratio=increase,"
                    f"crop={self._thumb_size}:{self._thumb_size}",
                    "-q:v", "6",
                    str(thumb_path),
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if not thumb_path.exists():
                return None, None
            return thumb_relative, f"/api/v1/uploads/{thumb_relative}"
        except Exception:
            return None, None

    async def _save_meal_images(
        self,
        meal_id: str,
        files: List[UploadFile],
    ) -> List[dict]:
        meal_dir = self._upload_root / meal_id
        meal_dir.mkdir(parents=True, exist_ok=True)
        now = datetime.utcnow()
        saved: List[dict] = []
        for upload in files:
            try:
                ext = self._validate_image_upload(upload)
                attachment_id = str(uuid.uuid4())
                storage_name = f"{attachment_id}{ext}"
                storage_path = meal_dir / storage_name
                with storage_path.open("wb") as out:
                    shutil.copyfileobj(upload.file, out)
                size_bytes = storage_path.stat().st_size
                safe_name = (upload.filename or storage_name).split("/")[-1].split("\\")[-1]
                relative_path = f"meals/{meal_id}/{storage_name}"
                thumb_path, thumb_url = self._generate_thumbnail(storage_path, meal_id, attachment_id)
                saved.append(
                    {
                        "attachment_id": attachment_id,
                        "filename": safe_name,
                        "content_type": upload.content_type or "image/jpeg",
                        "size_bytes": size_bytes,
                        "path": relative_path,
                        "url": f"/api/v1/uploads/{relative_path}",
                        "thumbnail_path": thumb_path,
                        "thumbnail_url": thumb_url,
                        "uploaded_at": format_utc_datetime(now),
                    }
                )
            finally:
                await upload.close()
        return saved

    # ============ Personalization helper ============

    async def _load_correction_hints(self, user_id: str, limit: int = 5) -> str:
        """Fetch the user's recent corrections and format them as a short prompt hint.

        v1 personalization: cheap few-shot bias. v2 will switch to image-embedding lookup.
        """
        db = get_database()
        cursor = db.meal_corrections.find({"user_id": user_id}).sort("created_at", -1).limit(limit)
        rows = await cursor.to_list(length=limit)
        if not rows:
            return ""
        examples: List[str] = []
        for row in rows:
            originals = [it.get("name", "") for it in row.get("original_food_items", []) if isinstance(it, dict)]
            corrected = [it.get("name", "") for it in row.get("corrected_food_items", []) if isinstance(it, dict)]
            if originals and corrected:
                examples.append(f"  Predicted: {', '.join(filter(None, originals))} → User had: {', '.join(filter(None, corrected))}")
        if not examples:
            return ""
        return (
            "\n\nPrior corrections from this user (use as soft bias when items look ambiguous):\n"
            + "\n".join(examples)
        )

    # ============ Analyze (vision) ============

    async def analyze_uploads(
        self,
        user_id: str,
        files: List[UploadFile],
        summary_text: Optional[str] = None,
    ) -> MealAnalyzeResponse:
        """
        Persist the uploaded photo(s) under uploads/meals/{meal_id}/ and return a
        structured analysis (food items + categorical macro ratios + meal-level
        fields).

        Two entry modes:

        1. `summary_text` provided (Lumie Meal-feature flow): the caller has
           already invoked `POST /api/v1/tasks/nutrition/analyze-images` to get
           the plain-text summary. We skip the vision call entirely and only run
           the meal-specific Step-7 structuring layer (text → categorical
           macros + meal_name + nutrition_level + advisor_insight). This is the
           strict spec path: vision goes through the proven Nutrition Task
           endpoint, never a parallel pipeline.

        2. `summary_text` omitted (legacy / Med-Reminder bridge path): we
           delegate the vision call to `task_service.analyze_nutrition_uploads`
           internally so the EXACT same prompt, model, fallback, and post-
           processing run as the working Nutrition Task flow. Then the same
           Step-7 structuring layer fires.

        The only meal-specific work in either mode is saving images to disk
        (needed for the /meals confirm step) and converting the resulting text
        summary into structured meal data via `_structure_text_to_meal`.
        """
        logger.info(
            "MealAnalyze ENTRY user_id=%s file_count=%d summary_text_len=%d",
            user_id, len(files or []),
            len((summary_text or "").strip()),
        )
        if not files:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No files uploaded",
            )
        if len(files) > 99:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="At most 99 files are allowed",
            )

        meal_id = str(uuid.uuid4())
        meal_dir = self._upload_root / meal_id
        meal_dir.mkdir(parents=True, exist_ok=True)
        now = datetime.utcnow()
        logger.info("MealAnalyze meal_id=%s prepared dir=%s", meal_id, meal_dir)

        images: List[dict] = []
        # Re-wrapped uploads (BytesIO-backed) to hand to the task pipeline. The
        # original `files` are consumed once we read their bytes, so we capture
        # the bytes here and use them for both disk persistence AND analysis.
        fresh_uploads: List[UploadFile] = []

        for upload in files:
            try:
                ext = self._validate_image_upload(upload)
                attachment_id = str(uuid.uuid4())
                storage_name = f"{attachment_id}{ext}"
                storage_path = meal_dir / storage_name

                data = await upload.read()
                if not data:
                    continue

                storage_path.write_bytes(data)
                size_bytes = storage_path.stat().st_size
                relative_path = f"meals/{meal_id}/{storage_name}"
                thumb_path, thumb_url = self._generate_thumbnail(
                    storage_path, meal_id, attachment_id,
                )
                safe_name = (
                    upload.filename or storage_name
                ).split("/")[-1].split("\\")[-1]
                content_type = upload.content_type or "image/jpeg"

                images.append(
                    {
                        "attachment_id": attachment_id,
                        "filename": safe_name,
                        "content_type": content_type,
                        "size_bytes": size_bytes,
                        "path": relative_path,
                        "url": f"/api/v1/uploads/{relative_path}",
                        "thumbnail_path": thumb_path,
                        "thumbnail_url": thumb_url,
                        "uploaded_at": format_utc_datetime(now),
                    }
                )

                # Same bytes, fresh stream. Cheap — bytes already in memory.
                fresh_uploads.append(
                    UploadFile(
                        filename=safe_name,
                        file=BytesIO(data),
                        headers=Headers({"content-type": content_type}),
                    )
                )
            finally:
                await upload.close()

        if not images:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Please upload at least one image file",
            )
        logger.info(
            "MealAnalyze meal_id=%s saved %d image(s); fresh_uploads=%d",
            meal_id, len(images), len(fresh_uploads),
        )

        provided_text = (summary_text or "").strip()
        if provided_text:
            # Caller already hit /tasks/nutrition/analyze-images and is passing
            # the resulting summary. Skip the vision call entirely.
            text_summary = provided_text
            logger.info(
                "MealAnalyze meal_id=%s mode=PROVIDED_TEXT len=%d",
                meal_id, len(provided_text),
            )
        else:
            # Legacy / bridge path: delegate the vision call to the working
            # Nutrition Task pipeline so the same prompt, same OpenAI payload,
            # same PaleBlueDot fallback, and same text sanitisation all run.
            logger.info(
                "MealAnalyze meal_id=%s mode=DELEGATE_TO_TASK_PIPELINE", meal_id,
            )
            from .task_service import task_service
            try:
                text_summary = await task_service.analyze_nutrition_uploads(fresh_uploads)
                logger.info(
                    "MealAnalyze meal_id=%s task pipeline returned len=%d",
                    meal_id, len(text_summary or ""),
                )
            except HTTPException:
                raise
            except Exception as exc:
                logger.warning(
                    "MealAnalyze meal_id=%s task pipeline raised: %s",
                    meal_id, exc,
                )
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail="Failed to analyze meal images",
                )

        # Convert the text summary into structured meal data. Same LLM call
        # the Med-Reminder → Meal bridge already uses, so the categorical
        # macros + meal_name + nutrition_level + advisor_insight are produced
        # consistently across both entry points. user_id is passed so prior
        # corrections from this user can bias the structuring (Step 8).
        logger.info(
            "MealAnalyze meal_id=%s structuring start text_len=%d",
            meal_id, len(text_summary or ""),
        )
        try:
            parsed = await self._structure_text_to_meal(
                text_summary, user_id=user_id,
            )
        except Exception as exc:
            logger.warning(
                "MealAnalyze meal_id=%s structuring raised: %s", meal_id, exc,
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Failed to structure meal analysis",
            )
        logger.info(
            "MealAnalyze meal_id=%s structuring OK food_items=%d "
            "macro_keys=%s meal_name='%s' nutrition_level=%s insight_len=%d",
            meal_id,
            len(parsed.get("food_items", [])),
            list((parsed.get("macro_ratio") or {}).keys()),
            (parsed.get("meal_name") or "")[:40],
            parsed.get("nutrition_level"),
            len(parsed.get("advisor_insight") or ""),
        )

        if not parsed["food_items"]:
            logger.warning(
                "MealAnalyze meal_id=%s NO food_items extracted from text=%r",
                meal_id, (text_summary or "")[:200],
            )
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="No food items could be identified from the image(s)",
            )

        return MealAnalyzeResponse(
            meal_id=meal_id,
            images=images,
            food_items=[FoodItem(**fi) for fi in parsed["food_items"]],
            macro_ratio=MacroRatio(**parsed["macro_ratio"]),
            meal_name=parsed.get("meal_name")
                or self._derive_meal_name_from_items(parsed["food_items"]),
            nutrition_level=(
                NutritionLevel(parsed["nutrition_level"])
                if parsed.get("nutrition_level")
                else self._derive_nutrition_level(
                    parsed["macro_ratio"],
                    processing_level=parsed.get("processing_level"),
                    added_sugar=parsed.get("added_sugar"),
                )
            ),
            advisor_insight=parsed.get("advisor_insight") or None,
            # Default to MODERATE on missing — neutral baseline that doesn't
            # bias the user's perception of their meal.
            processing_level=MacroLevel(
                parsed.get("processing_level") or MacroLevel.MODERATE.value
            ),
            added_sugar=MacroLevel(
                parsed.get("added_sugar") or MacroLevel.LOW.value
            ),
        )

    async def restructure_food_list(
        self,
        user_id: str,
        food_items: List[FoodItem],
    ) -> dict:
        """Re-run the structuring layer against a user-edited food list with
        portion weights, without re-running vision. Used by the Log screen
        Re-analyze button: the meal isn't yet confirmed, so we don't update
        any DB row — we just hand back the refreshed analysis fields. The
        Detail screen flows through update_meal instead since the meal is
        already persisted there.
        """
        if not food_items:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="At least one food item is required",
            )

        items_dump = [fi.model_dump() for fi in food_items]
        has_portion_signal = any(
            int(fi.get("portion_weight", 1) or 1) != 1
            for fi in items_dump
        )
        if has_portion_signal:
            synthetic_text = ", ".join(
                f"{str(fi.get('name', '')).strip()} (portion {int(fi.get('portion_weight', 1) or 1)})"
                for fi in items_dump
                if fi.get("name")
            )
        else:
            synthetic_text = ", ".join(
                str(fi.get("name", "")).strip()
                for fi in items_dump
                if fi.get("name")
            )
        if not synthetic_text:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No food items provided",
            )

        try:
            parsed = await self._structure_text_to_meal(
                synthetic_text, user_id=user_id,
            )
        except Exception as exc:
            logger.warning(
                "Restructure failed user_id=%s text=%r exc=%s",
                user_id, synthetic_text[:120], exc,
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Failed to re-analyze meal",
            )

        if not parsed.get("food_items"):
            # Structuring returned nothing parseable — preserve the user's
            # foods so they don't lose their edits, and fall back to the
            # deterministic level derivation.
            parsed = {
                "food_items": items_dump,
                "macro_ratio": parsed.get("macro_ratio") or {
                    "protein": "moderate",
                    "carbs": "moderate",
                    "fat": "moderate",
                    "fiber": "low",
                },
                "meal_name": parsed.get("meal_name"),
                "nutrition_level": parsed.get("nutrition_level"),
                "advisor_insight": parsed.get("advisor_insight"),
                "processing_level": parsed.get("processing_level"),
                "added_sugar": parsed.get("added_sugar"),
            }

        # Always preserve the user's typed names + portion weights — the LLM
        # may have re-cased or re-ordered, but the user's deliberate edits win.
        out_items = []
        for i, fi in enumerate(items_dump):
            llm_item = parsed["food_items"][i] if i < len(parsed["food_items"]) else {}
            out_items.append({
                "name": fi.get("name", ""),
                "portion_weight": int(fi.get("portion_weight", 1) or 1),
                "macro_ratio": llm_item.get("macro_ratio") if isinstance(llm_item, dict) else None,
            })
        parsed["food_items"] = out_items

        return parsed

    def _parse_analysis_json(self, raw_text: str) -> dict:
        """Tolerant JSON extraction. Returns
        {food_items, macro_ratio, meal_name, nutrition_level, advisor_insight}
        with safe defaults so a partial LLM response never breaks the flow."""
        text = (raw_text or "").strip()
        start, end = text.find("{"), text.rfind("}")
        if start != -1 and end != -1 and end > start:
            text = text[start : end + 1]
        try:
            data = json.loads(text)
        except Exception:
            data = {}

        valid_levels = {lvl.value for lvl in MacroLevel}
        valid_nutrition = {lvl.value for lvl in NutritionLevel}

        def coerce_ratio(obj: Any) -> dict:
            obj = obj if isinstance(obj, dict) else {}
            return {
                "protein": obj.get("protein") if obj.get("protein") in valid_levels else "moderate",
                "carbs": obj.get("carbs") if obj.get("carbs") in valid_levels else "moderate",
                "fat": obj.get("fat") if obj.get("fat") in valid_levels else "moderate",
                "fiber": obj.get("fiber") if obj.get("fiber") in valid_levels else "low",
            }

        items_in = data.get("food_items") if isinstance(data, dict) else None
        items_in = items_in if isinstance(items_in, list) else []
        food_items: List[dict] = []
        for it in items_in:
            if not isinstance(it, dict):
                continue
            name = str(it.get("name", "")).strip()
            if not name:
                continue
            raw_weight = it.get("portion_weight")
            if isinstance(raw_weight, bool):
                weight = 1
            elif isinstance(raw_weight, int):
                weight = raw_weight
            elif isinstance(raw_weight, float):
                weight = int(round(raw_weight))
            elif isinstance(raw_weight, str):
                try:
                    weight = int(float(raw_weight))
                except Exception:
                    weight = 1
            else:
                weight = 1
            if weight < 1:
                weight = 1
            if weight > 20:
                weight = 20
            food_items.append({
                "name": name[:200],
                "macro_ratio": coerce_ratio(it.get("macro_ratio")),
                "portion_weight": weight,
            })

        meal_ratio = coerce_ratio(data.get("macro_ratio") if isinstance(data, dict) else None)

        meal_name_raw = data.get("meal_name") if isinstance(data, dict) else None
        meal_name = str(meal_name_raw).strip()[:120] if isinstance(meal_name_raw, str) else ""

        level_raw = data.get("nutrition_level") if isinstance(data, dict) else None
        nutrition_level = level_raw if level_raw in valid_nutrition else None

        insight_raw = data.get("advisor_insight") if isinstance(data, dict) else None
        advisor_insight = str(insight_raw).strip()[:600] if isinstance(insight_raw, str) else ""

        # Slice 7A: processing_level + added_sugar (low/moderate/high). Coerce
        # the same way as macros so a partial LLM response can't break the flow.
        proc_raw = data.get("processing_level") if isinstance(data, dict) else None
        processing_level = proc_raw if proc_raw in valid_levels else None
        sugar_raw = data.get("added_sugar") if isinstance(data, dict) else None
        added_sugar = sugar_raw if sugar_raw in valid_levels else None

        return {
            "food_items": food_items,
            "macro_ratio": meal_ratio,
            "meal_name": meal_name,
            "nutrition_level": nutrition_level,
            "advisor_insight": advisor_insight,
            "processing_level": processing_level,
            "added_sugar": added_sugar,
        }

    # ============ CRUD ============

    def _meal_doc_to_response(self, doc: dict, user_name: Optional[str] = None) -> MealResponse:
        food_items_raw = doc.get("food_items", [])
        macro_ratio_raw = doc.get("macro_ratio", {})

        # On-read derivation for legacy meals that pre-date the v2 fields.
        meal_name = doc.get("meal_name") or self._derive_meal_name_from_items(food_items_raw)
        meal_time_raw = doc.get("meal_time") or format_utc_datetime(doc["created_at"])

        meal_type_raw = doc.get("meal_type")
        if meal_type_raw not in {t.value for t in MealType}:
            # Legacy meal: bucket by created_at in UTC (good enough for back-fill).
            meal_type_raw = self._derive_meal_type_from_local_dt(doc["created_at"]).value

        level_raw = doc.get("nutrition_level")
        if level_raw not in {l.value for l in NutritionLevel}:
            level_raw = self._derive_nutrition_level(
                macro_ratio_raw,
                processing_level=doc.get("processing_level"),
                added_sugar=doc.get("added_sugar"),
            ).value

        # Slice 7A: legacy meals lacking processing_level / added_sugar default
        # to MODERATE / LOW respectively (neutral baseline that doesn't bias
        # the user's perception).
        valid_macro_levels = {lvl.value for lvl in MacroLevel}
        proc_raw = doc.get("processing_level")
        if proc_raw not in valid_macro_levels:
            proc_raw = MacroLevel.MODERATE.value
        sugar_raw = doc.get("added_sugar")
        if sugar_raw not in valid_macro_levels:
            sugar_raw = MacroLevel.LOW.value

        return MealResponse(
            meal_id=doc["meal_id"],
            user_id=doc["user_id"],
            user_name=user_name,
            images=doc.get("images", []),
            food_items=[FoodItem(**fi) for fi in food_items_raw],
            macro_ratio=MacroRatio(**macro_ratio_raw),
            note=doc.get("note"),
            visibility=MealVisibility(doc.get("visibility", "private")),
            team_id=doc.get("team_id"),
            linked_task_id=doc.get("linked_task_id"),
            meal_name=meal_name,
            meal_type=MealType(meal_type_raw),
            meal_time=meal_time_raw,
            nutrition_level=NutritionLevel(level_raw),
            advisor_insight=doc.get("advisor_insight"),
            processing_level=MacroLevel(proc_raw),
            added_sugar=MacroLevel(sugar_raw),
            created_at=format_utc_datetime(doc["created_at"]),
            updated_at=format_utc_datetime(doc["updated_at"]),
        )

    async def _resolve_user_name(self, user_id: str) -> Optional[str]:
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        return profile.get("name") if profile else None

    async def _verify_team_membership(self, team_id: str, user_id: str) -> None:
        db = get_database()
        member = await db.team_members.find_one({
            "team_id": team_id,
            "user_id": user_id,
            "status": MemberStatus.MEMBER.value,
        })
        if not member:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not an active member of this team",
            )

    def _scan_meal_images(self, meal_id: str) -> List[dict]:
        """Re-scan the filesystem under uploads/meals/{meal_id}/ to rebuild the
        attachment list at create time. Avoids the client having to round-trip
        the (potentially large) image metadata array."""
        meal_dir = self._upload_root / meal_id
        if not meal_dir.exists():
            return []
        images: List[dict] = []
        for file_path in sorted(meal_dir.iterdir()):
            if not file_path.is_file():
                continue
            name = file_path.name
            if name.endswith("_thumb.jpg"):
                continue
            stem = file_path.stem  # attachment_id (uuid)
            ext = file_path.suffix.lower()
            content_type = "image/jpeg"
            if ext in (".png",):
                content_type = "image/png"
            elif ext in (".webp",):
                content_type = "image/webp"
            elif ext in (".heic",):
                content_type = "image/heic"
            relative_path = f"meals/{meal_id}/{name}"
            thumb_relative = f"meals/{meal_id}/{stem}_thumb.jpg"
            thumb_path = self._upload_root / meal_id / f"{stem}_thumb.jpg"
            images.append(
                {
                    "attachment_id": stem,
                    "filename": name,
                    "content_type": content_type,
                    "size_bytes": file_path.stat().st_size,
                    "path": relative_path,
                    "url": f"/api/v1/uploads/{relative_path}",
                    "thumbnail_path": thumb_relative if thumb_path.exists() else None,
                    "thumbnail_url": f"/api/v1/uploads/{thumb_relative}" if thumb_path.exists() else None,
                    "uploaded_at": format_utc_datetime(datetime.utcfromtimestamp(file_path.stat().st_mtime)),
                }
            )
        return images

    @staticmethod
    def _food_lists_equal_with_portions(a: list, b: list) -> bool:
        """Positional comparison including portion_weight.

        Returns True only when name AND portion_weight are identical
        position-by-position. Any rename, deletion, addition, reorder, OR
        portion-bar adjustment makes the lists unequal — which triggers
        re-analysis on any single user-visible change to the food list
        (including pure portion edits with no rename).
        """
        a = a or []
        b = b or []
        if len(a) != len(b):
            return False
        for ai, bi in zip(a, b):
            ai_name = (ai.get("name") or "").strip() if isinstance(ai, dict) else ""
            bi_name = (bi.get("name") or "").strip() if isinstance(bi, dict) else ""
            if ai_name != bi_name:
                return False
            ai_w = ai.get("portion_weight", 1) if isinstance(ai, dict) else 1
            bi_w = bi.get("portion_weight", 1) if isinstance(bi, dict) else 1
            if int(ai_w or 1) != int(bi_w or 1):
                return False
        return True

    @staticmethod
    def _food_lists_equal(a: list, b: list) -> bool:
        """Positional, trim-only name comparison.

        Returns True ONLY when the two lists are identical position-by-position
        after stripping surrounding whitespace. ANY single rename, deletion,
        addition, or reorder makes the lists unequal — which triggers
        re-analysis on the smallest possible edit. Mirrors the frontend's
        `_hasFoodEdits` so the user's "Re-analyze" button and the backend's
        re-structuring decision can never disagree.
        """
        a = a or []
        b = b or []
        if len(a) != len(b):
            return False
        for ai, bi in zip(a, b):
            ai_name = (ai.get("name") or "").strip() if isinstance(ai, dict) else ""
            bi_name = (bi.get("name") or "").strip() if isinstance(bi, dict) else ""
            if ai_name != bi_name:
                return False
        return True

    @staticmethod
    def _food_preview(food_items: list) -> str:
        """Short '·'-joined preview used in dayprint events and team feed cards."""
        names = [
            (fi.get("name") if isinstance(fi, dict) else getattr(fi, "name", ""))
            for fi in (food_items or [])
        ]
        names = [n for n in names if n]
        if not names:
            return "Meal"
        preview = " · ".join(names[:3])
        if len(names) > 3:
            preview += f" · +{len(names) - 3}"
        return preview

    # ============ Derivation helpers (used as fallbacks when LLM didn't provide) ============

    @staticmethod
    def _derive_meal_name_from_items(food_items: list) -> str:
        """Fallback meal name from the first 1-2 food item names."""
        names = [
            (fi.get("name") if isinstance(fi, dict) else getattr(fi, "name", ""))
            for fi in (food_items or [])
        ]
        names = [n for n in names if n]
        if not names:
            return "Meal"
        if len(names) == 1:
            return names[0]
        return f"{names[0]} & {names[1]}"

    @staticmethod
    def _derive_meal_type_from_local_dt(dt: datetime) -> MealType:
        """Map a local datetime to a meal type. Boundaries chosen for teen schedules."""
        h = dt.hour + dt.minute / 60.0
        if 4.0 <= h < 10.5:
            return MealType.BREAKFAST
        if 10.5 <= h < 14.5:
            return MealType.LUNCH
        if 17.0 <= h < 22.0:
            return MealType.DINNER
        return MealType.SNACK

    @staticmethod
    def _derive_nutrition_level(
        macro_ratio: dict,
        processing_level: Optional[str] = None,
        added_sugar: Optional[str] = None,
    ) -> NutritionLevel:
        """Deterministic nutrition-level fallback when the LLM didn't return one.

        Calibrated to be PERMISSIVE per the grading philosophy: a meal does not
        need to be perfect to be Nutritious. Default upward — assign Nutritious
        to any meal that is reasonably balanced and minimally processed; reserve
        Limited for meals that are genuinely ultra-processed AND high in added
        sugar.

        Tier rules:
          • Limited: high processing AND high added sugar (e.g. white bread
            with sugary peanut butter, fast food with sweetened soda)
          • Fair: ultra-processed alone, OR moderate processing combined with
            high added sugar (e.g. natural nut butter on white bread, fast food
            burger that isn't sugar-heavy)
          • Nutritious: minimally processed AND ≥3 of the four macros at
            moderate-or-above (e.g. salmon + greens + rice; whole-wheat toast
            with natural nut butter; eggs with vegetables)
          • Good: minimally processed but fewer macros at moderate-or-above
            (e.g. fruit, plain crackers, a handful of nuts as a snack)

        When `processing_level` / `added_sugar` are unknown, we lean upward
        (treat them as not-high) so legacy meals don't get unfairly penalised.
        """
        weights = {"low": 1, "moderate": 2, "high": 3}
        if not isinstance(macro_ratio, dict):
            return NutritionLevel.GOOD

        macros_at_moderate_or_above = sum(
            1
            for k in ("protein", "carbs", "fat", "fiber")
            if weights.get(macro_ratio.get(k), 2) >= 2
        )

        high_proc = processing_level == "high"
        mod_proc = processing_level == "moderate"
        high_sugar = added_sugar == "high"

        # Hard floor: ultra-processed AND sugar-heavy.
        if high_proc and high_sugar:
            return NutritionLevel.LIMITED
        # Either ultra-processed alone, or moderately processed with high sugar.
        if high_proc or (mod_proc and high_sugar):
            return NutritionLevel.FAIR

        # Minimally processed (low / unknown) — default upward.
        if macros_at_moderate_or_above >= 3:
            return NutritionLevel.NUTRITIOUS
        return NutritionLevel.GOOD

    @staticmethod
    def _nutrition_level_score(level: Optional[str]) -> Optional[int]:
        return {
            NutritionLevel.LIMITED.value: 1,
            NutritionLevel.FAIR.value: 2,
            NutritionLevel.GOOD.value: 3,
            NutritionLevel.NUTRITIOUS.value: 4,
        }.get(level)

    @staticmethod
    def _nutrition_level_from_score(avg: float) -> NutritionLevel:
        rounded = round(avg)
        if rounded <= 1:
            return NutritionLevel.LIMITED
        if rounded == 2:
            return NutritionLevel.FAIR
        if rounded == 3:
            return NutritionLevel.GOOD
        return NutritionLevel.NUTRITIOUS

    async def _resolve_user_timezone(self, user_id: str) -> str:
        db = get_database()
        profile = await db.profiles.find_one({"user_id": user_id})
        return (profile or {}).get("timezone") or "UTC"

    @staticmethod
    def _parse_task_local_dt(task: dict) -> Optional[datetime]:
        """Extract a usable datetime anchor from a Nutrition task. Tasks store
        open_datetime as 'YYYY-MM-DD HH:MM' UTC strings; completed_at as a real
        datetime. Returns the most informative one available."""
        completed = task.get("completed_at")
        if isinstance(completed, datetime):
            return completed
        open_dt = task.get("open_datetime")
        if isinstance(open_dt, str):
            try:
                return datetime.strptime(open_dt, "%Y-%m-%d %H:%M")
            except ValueError:
                pass
        return None

    @staticmethod
    def _safe_zone(name: str) -> ZoneInfo:
        try:
            return ZoneInfo(name)
        except Exception:
            return ZoneInfo("UTC")

    async def create_meal(self, user_id: str, data: MealCreate) -> MealResponse:
        db = get_database()

        # Idempotency: if the meal_id was already confirmed, refuse rather than overwrite.
        existing = await db.meals.find_one({"meal_id": data.meal_id})
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Meal with this ID already exists",
            )

        # Visibility/team consistency
        team_id: Optional[str] = None
        if data.visibility == MealVisibility.TEAM:
            if not data.team_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="team_id is required when visibility='team'",
                )
            await self._verify_team_membership(data.team_id, user_id)
            team_id = data.team_id

        images = self._scan_meal_images(data.meal_id)
        if not images and not data.linked_task_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No images found for this meal_id. Call POST /meals/analyze first.",
            )

        now = datetime.utcnow()

        # Derive any v2 fields the client didn't pass. Client passes through
        # whatever it got from /meals/analyze; the bridge passes nothing and
        # relies entirely on these defaults.
        food_items_dump = [fi.model_dump() for fi in data.food_items]
        macro_ratio_dump = data.macro_ratio.model_dump()

        meal_name = (data.meal_name or "").strip() or self._derive_meal_name_from_items(food_items_dump)

        if data.meal_type is not None:
            meal_type_value = data.meal_type.value
        else:
            tz_name = data.timezone or await self._resolve_user_timezone(user_id)
            local_now = now.replace(tzinfo=timezone.utc).astimezone(self._safe_zone(tz_name))
            meal_type_value = self._derive_meal_type_from_local_dt(local_now).value

        meal_time_value = data.meal_time or format_utc_datetime(now)

        advisor_insight_value = (data.advisor_insight or "").strip() or None

        # Slice 7A: processing_level + added_sugar pass through from analyze;
        # default moderate / low respectively when caller didn't provide.
        # Derived BEFORE nutrition_level so the recalibrated fallback can use
        # them (a meal that's high-processing + high-sugar floors to Limited).
        processing_level_value = (
            data.processing_level.value
            if data.processing_level is not None
            else MacroLevel.MODERATE.value
        )
        added_sugar_value = (
            data.added_sugar.value
            if data.added_sugar is not None
            else MacroLevel.LOW.value
        )

        if data.nutrition_level is not None:
            nutrition_level_value = data.nutrition_level.value
        else:
            nutrition_level_value = self._derive_nutrition_level(
                macro_ratio_dump,
                processing_level=processing_level_value,
                added_sugar=added_sugar_value,
            ).value

        # Strict identity rule: a meal carrying linked_task_id IS a Nutrition-
        # task meal — must be stamped with source_type/source_task_id so it
        # uses the canonical identity everywhere (Meals API dedupe, dayprint
        # source_key, migration grouping). Without this, a manual /meals POST
        # with linked_task_id and a later bridge call produced two parallel
        # representations with different canonical keys.
        source_type_value: Optional[str] = None
        source_task_id_value: Optional[str] = None
        if data.linked_task_id:
            source_type_value = "nutrition_task"
            source_task_id_value = data.linked_task_id

        doc = {
            "meal_id": data.meal_id,
            "user_id": user_id,
            "images": images,
            "food_items": food_items_dump,
            "macro_ratio": macro_ratio_dump,
            "note": data.note,
            "visibility": data.visibility.value,
            "team_id": team_id,
            "linked_task_id": data.linked_task_id,
            "meal_name": meal_name,
            "meal_type": meal_type_value,
            "meal_time": meal_time_value,
            "nutrition_level": nutrition_level_value,
            "advisor_insight": advisor_insight_value,
            "processing_level": processing_level_value,
            "added_sugar": added_sugar_value,
            "created_at": now,
            "updated_at": now,
        }
        if source_type_value:
            doc["source_type"] = source_type_value
            doc["source_task_id"] = source_task_id_value
        await db.meals.insert_one(doc)

        # Mark the moment this meal entered the user's day. Fire-and-forget
        # so dayprint write failures never break meal creation. Pass the
        # canonical source identity so the dayprint event's source_key
        # collapses with any bridge-emitted event for the same task.
        first_image_url = images[0]["url"] if images else None
        try:
            await log_meal_logged(
                user_id=user_id,
                meal_id=data.meal_id,
                food_preview=self._food_preview(doc["food_items"]),
                image_url=first_image_url,
                visibility=data.visibility.value,
                team_id=team_id,
                source_type=source_type_value or "meal",
                source_task_id=source_task_id_value,
            )
        except Exception as exc:
            logger.warning("Dayprint log_meal_logged failed for %s: %s", user_id, exc)

        user_name = await self._resolve_user_name(user_id)
        return self._meal_doc_to_response(doc, user_name=user_name)

    async def get_meal(self, meal_id: str, user_id: str) -> MealResponse:
        db = get_database()
        doc = await db.meals.find_one({"meal_id": meal_id})
        if not doc:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meal not found")

        # Owner can always read; team members can read if visibility=team
        if doc["user_id"] != user_id:
            if doc.get("visibility") == MealVisibility.TEAM.value and doc.get("team_id"):
                await self._verify_team_membership(doc["team_id"], user_id)
            else:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You do not have permission to view this meal",
                )

        user_name = await self._resolve_user_name(doc["user_id"])
        return self._meal_doc_to_response(doc, user_name=user_name)

    async def update_meal(self, meal_id: str, user_id: str, data: MealUpdate) -> MealResponse:
        db = get_database()
        doc = await db.meals.find_one({"meal_id": meal_id})
        if not doc:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meal not found")
        if doc["user_id"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the meal owner can edit this meal",
            )

        # When food_items changed, the request is a re-analyze: only nutrition
        # fields may move. The original logged_at (meal_time / meal_type) and
        # created_at must be preserved so the meal stays anchored to when the
        # user actually ate, not when they re-analyzed.
        is_reanalyze = (
            data.food_items is not None
            and not self._food_lists_equal_with_portions(
                doc.get("food_items", []),
                [fi.model_dump() for fi in data.food_items],
            )
        )

        updates: dict = {}
        if data.food_items is not None:
            updates["food_items"] = [fi.model_dump() for fi in data.food_items]
        if data.macro_ratio is not None:
            updates["macro_ratio"] = data.macro_ratio.model_dump()
        if data.note is not None:
            updates["note"] = data.note
        if data.meal_name is not None:
            updates["meal_name"] = data.meal_name.strip()
        if data.meal_type is not None and not is_reanalyze:
            updates["meal_type"] = data.meal_type.value
        if data.meal_time is not None and not is_reanalyze:
            updates["meal_time"] = data.meal_time
        if data.nutrition_level is not None:
            updates["nutrition_level"] = data.nutrition_level.value
        if data.advisor_insight is not None:
            updates["advisor_insight"] = data.advisor_insight
        if data.processing_level is not None:
            updates["processing_level"] = data.processing_level.value
        if data.added_sugar is not None:
            updates["added_sugar"] = data.added_sugar.value

        # Slice 7A §7: when food_items changed, re-run the structuring layer
        # against the new list so all six macro rows + nutrition_level +
        # meal_name + advisor_insight refresh to reflect the corrected foods.
        # A whole-food correction in place of a processed equivalent will
        # therefore produce a meaningfully different nutrition_level.
        # Caller-provided values still win — re-analysis only fills fields
        # the caller didn't explicitly override.
        if is_reanalyze:
            new_foods_dump = updates["food_items"]
            has_portion_signal = any(
                int(fi.get("portion_weight", 1) or 1) != 1
                for fi in new_foods_dump
            )
            if has_portion_signal:
                synthetic_text = ", ".join(
                    f"{str(fi.get('name', '')).strip()} (portion {int(fi.get('portion_weight', 1) or 1)})"
                    for fi in new_foods_dump
                    if fi.get("name")
                )
            else:
                synthetic_text = ", ".join(
                    str(fi.get("name", "")).strip()
                    for fi in new_foods_dump
                    if fi.get("name")
                )
            if synthetic_text:
                logger.info(
                    "Update re-analysing meal_id=%s with new foods text=%r",
                    meal_id, synthetic_text[:120],
                )
                try:
                    re_parsed = await self._structure_text_to_meal(
                        synthetic_text, user_id=user_id,
                    )
                    if data.macro_ratio is None and re_parsed.get("macro_ratio"):
                        updates["macro_ratio"] = re_parsed["macro_ratio"]
                    if data.nutrition_level is None and re_parsed.get("nutrition_level"):
                        updates["nutrition_level"] = re_parsed["nutrition_level"]
                    if data.meal_name is None and re_parsed.get("meal_name"):
                        updates["meal_name"] = re_parsed["meal_name"]
                    if data.advisor_insight is None and re_parsed.get("advisor_insight"):
                        updates["advisor_insight"] = re_parsed["advisor_insight"]
                    if data.processing_level is None and re_parsed.get("processing_level"):
                        updates["processing_level"] = re_parsed["processing_level"]
                    if data.added_sugar is None and re_parsed.get("added_sugar"):
                        updates["added_sugar"] = re_parsed["added_sugar"]
                    logger.info(
                        "Update re-analysed meal_id=%s "
                        "nutrition_level=%s meal_name='%s'",
                        meal_id,
                        re_parsed.get("nutrition_level"),
                        (re_parsed.get("meal_name") or "")[:40],
                    )
                except Exception as exc:
                    logger.warning(
                        "Re-analysis on update failed for meal_id=%s: %s",
                        meal_id, exc,
                    )
                    # Fall through — the food edit still saves; we just
                    # skip the structured refresh.

        # Visibility / team transitions
        new_visibility = data.visibility.value if data.visibility is not None else doc.get("visibility")
        new_team_id = doc.get("team_id")
        if "team_id" in data.model_fields_set:
            new_team_id = data.team_id
        if data.visibility is not None:
            updates["visibility"] = new_visibility
        if "team_id" in data.model_fields_set:
            updates["team_id"] = new_team_id

        if new_visibility == MealVisibility.TEAM.value:
            if not new_team_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="team_id is required when visibility='team'",
                )
            await self._verify_team_membership(new_team_id, user_id)
        elif new_visibility == MealVisibility.PRIVATE.value:
            updates["team_id"] = None  # auto-detach when going private

        if not updates:
            return self._meal_doc_to_response(doc, user_name=await self._resolve_user_name(user_id))

        # Flip user_edited so future Med-Reminder→Meal bridge syncs leave this
        # meal alone. The user has manually adjusted it; their edits win.
        updates["user_edited"] = True
        updates["updated_at"] = datetime.utcnow()
        await db.meals.update_one({"meal_id": meal_id}, {"$set": updates})
        updated = await db.meals.find_one({"meal_id": meal_id})

        # Strict "Meal = Dayprint event" rule: any time the meal mutates we
        # also refresh the linked dayprint event payload so the dayprint
        # never renders stale food_preview / image data. The helper is
        # an in-place update keyed on canonical source_key — it does NOT
        # create a new event for meals that were never previously logged
        # to dayprint, so re-analyses against legacy meals are safe.
        try:
            images = updated.get("images") or []
            first_image_url = images[0].get("url") if images else None
            source_task = (
                updated.get("source_task_id") or updated.get("linked_task_id")
            )
            await refresh_dayprint_event_for_meal(
                user_id=user_id,
                meal_id=meal_id,
                food_preview=self._food_preview(updated.get("food_items") or []),
                image_url=first_image_url,
                visibility=updated.get("visibility") or MealVisibility.PRIVATE.value,
                team_id=updated.get("team_id"),
                source_type=(
                    "nutrition_task" if source_task else "meal"
                ),
                source_task_id=source_task,
            )
        except Exception as exc:
            logger.warning(
                "Dayprint refresh after update_meal failed for %s: %s",
                meal_id, exc,
            )

        return self._meal_doc_to_response(updated, user_name=await self._resolve_user_name(user_id))

    async def delete_meal(self, meal_id: str, user_id: str) -> dict:
        db = get_database()
        doc = await db.meals.find_one({"meal_id": meal_id})
        if not doc:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meal not found")
        if doc["user_id"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the meal owner can delete this meal",
            )
        await db.meals.delete_one({"meal_id": meal_id})

        # Best-effort cleanup of the on-disk directory; ignore errors so a bad
        # filesystem state doesn't block the DB delete.
        meal_dir = self._upload_root / meal_id
        if meal_dir.exists():
            try:
                shutil.rmtree(meal_dir)
            except Exception as exc:
                logger.warning("Failed to remove meal directory %s: %s", meal_dir, exc)

        return {"message": "Meal deleted"}

    # ============ Listing & feed ============

    @staticmethod
    def _parse_cursor(before: Optional[str]) -> Optional[datetime]:
        if not before:
            return None
        try:
            # Accept both '2026-05-03T12:00:00Z' and '2026-05-03T12:00:00'
            return datetime.fromisoformat(before.replace("Z", ""))
        except ValueError:
            return None

    @staticmethod
    def _meal_canonical_identity(doc: dict) -> str:
        """Canonical identity used to dedupe duplicate rows at API time.

        Mirrors the dayprint scheme so a Meal and its Dayprint event always
        share one identity:

            • task-linked meal  → "nutrition_task:<user_id>:<task_id>"
            • normal manual     → "meal:<meal_id>"

        A meal is task-linked when ANY of these is true (in priority order):
            1. `source_type` starts with "nutrition_task" with a `source_task_id`
            2. `source_task_id` exists
            3. `linked_task_id` exists

        Rule 3 is essential — legacy `POST /meals` calls written before
        `create_meal` learned to canonicalize stored `linked_task_id` only,
        and they MUST resolve to the same identity as the bridge-stamped
        meal for the same task. Otherwise the Meals page shows two cards
        (one with picture from the bridge, one without from the manual save)
        for what is logically the same Nutrition task.
        """
        user_id = doc.get("user_id") or ""
        task_id = (
            doc.get("source_task_id")
            or doc.get("linked_task_id")
        )
        if task_id:
            return f"nutrition_task:{user_id}:{task_id}"
        return f"meal:{doc.get('meal_id')}"

    @classmethod
    def _dedupe_meal_docs(cls, docs: list[dict]) -> list[dict]:
        """Collapse duplicate rows by canonical identity, keeping the oldest
        (canonical) row but MERGING image / food data from siblings so the
        surviving card always carries the richest user-visible state.
        Manually-logged meals (no task link) never collapse with each other.
        """
        groups: dict[str, list[dict]] = {}
        order: list[str] = []
        for doc in docs:
            identity = cls._meal_canonical_identity(doc)
            if identity not in groups:
                groups[identity] = []
                order.append(identity)
            groups[identity].append(doc)

        result: list[dict] = []
        collapsed = 0
        for identity in order:
            group = groups[identity]
            if len(group) == 1:
                result.append(group[0])
                continue
            ordered = sorted(group, key=cls._meal_age_key)
            canonical = dict(ordered[0])  # oldest created_at wins (id/timestamps)
            # Display source: prefer a row that has a picture — that's the
            # bridge-written row carrying the freshest task-derived data.
            # Falls back to canonical if no row has images.
            display = next((m for m in ordered if m.get("images")), canonical)
            if display.get("images"):
                canonical["images"] = display["images"]
            if display.get("food_items"):
                canonical["food_items"] = display["food_items"]
            if not canonical.get("note"):
                for sibling in ordered[1:]:
                    if sibling.get("note"):
                        canonical["note"] = sibling["note"]
                        break
            collapsed += len(group) - 1
            result.append(canonical)

        if collapsed:
            logger.info(
                "Meals API defensive dedupe collapsed %d duplicate row(s)",
                collapsed,
            )
        return result

    def _log_returned_meals(self, label: str, docs: list[dict]) -> None:
        """Per-meal canonical-identity log line so production traces can
        prove the API only emits one row per identity. Cheap; one INFO
        line per meal returned.
        """
        for doc in docs:
            logger.info(
                "MealsAPI %s meal_id=%s identity=%s source_type=%s "
                "source_task_id=%s user_id=%s created_at=%s meal_time=%s",
                label,
                doc.get("meal_id"),
                self._meal_canonical_identity(doc),
                doc.get("source_type"),
                doc.get("source_task_id") or doc.get("linked_task_id"),
                doc.get("user_id"),
                doc.get("created_at"),
                doc.get("meal_time"),
            )

    async def list_user_meals(
        self,
        user_id: str,
        limit: int = 20,
        before: Optional[str] = None,
    ) -> MealListResponse:
        db = get_database()
        query: dict = {"user_id": user_id}
        cursor_dt = self._parse_cursor(before)
        if cursor_dt is not None:
            query["created_at"] = {"$lt": cursor_dt}

        # Over-fetch so the dedupe pass cannot collapse the response below
        # `limit` and starve the page. We trim back after dedup.
        fetch_limit = (limit + 1) * 2
        cursor = db.meals.find(query).sort("created_at", -1).limit(fetch_limit)
        raw_docs = await cursor.to_list(length=fetch_limit)
        deduped = self._dedupe_meal_docs(raw_docs)
        self._log_returned_meals("list_user_meals", deduped)

        next_cursor: Optional[str] = None
        if len(deduped) > limit:
            deduped = deduped[:limit]
            next_cursor = format_utc_datetime(deduped[-1]["created_at"])

        user_name = await self._resolve_user_name(user_id)
        return MealListResponse(
            meals=[self._meal_doc_to_response(d, user_name=user_name) for d in deduped],
            total=len(deduped),
            next_cursor=next_cursor,
        )

    async def get_team_feed(
        self,
        team_id: str,
        user_id: str,
        limit: int = 20,
        before: Optional[str] = None,
    ) -> MealListResponse:
        db = get_database()
        await self._verify_team_membership(team_id, user_id)

        query: dict = {
            "team_id": team_id,
            "visibility": MealVisibility.TEAM.value,
        }
        cursor_dt = self._parse_cursor(before)
        if cursor_dt is not None:
            query["created_at"] = {"$lt": cursor_dt}

        fetch_limit = (limit + 1) * 2
        cursor = db.meals.find(query).sort("created_at", -1).limit(fetch_limit)
        raw_docs = await cursor.to_list(length=fetch_limit)
        deduped = self._dedupe_meal_docs(raw_docs)
        self._log_returned_meals("get_team_feed", deduped)

        next_cursor: Optional[str] = None
        if len(deduped) > limit:
            deduped = deduped[:limit]
            next_cursor = format_utc_datetime(deduped[-1]["created_at"])

        # Resolve user_name per meal — small N, simple loop.
        name_cache: dict[str, Optional[str]] = {}
        meals: List[MealResponse] = []
        for d in deduped:
            uid = d["user_id"]
            if uid not in name_cache:
                name_cache[uid] = await self._resolve_user_name(uid)
            meals.append(self._meal_doc_to_response(d, user_name=name_cache[uid]))

        return MealListResponse(meals=meals, total=len(meals), next_cursor=next_cursor)

    # ============ Trend ============

    async def get_trend(self, user_id: str, days: int = 7) -> MealTrendResponse:
        """Weekly nutrition trend: one bucket per local-calendar day, oldest first.

        Each bucket carries the average nutrition_level (mapped back to the
        nearest categorical level) and the meal count for that day. Days with
        zero meals return level=null so the chart can render a gap.
        """
        days = max(1, min(days, 31))
        db = get_database()
        tz_name = await self._resolve_user_timezone(user_id)
        zone = self._safe_zone(tz_name)

        # Local-day boundaries
        today_local = datetime.now(zone).date()
        start_local_date = today_local - timedelta(days=days - 1)
        start_local_dt = datetime(
            start_local_date.year, start_local_date.month, start_local_date.day,
            tzinfo=zone,
        )
        end_local_dt = datetime(
            today_local.year, today_local.month, today_local.day,
            tzinfo=zone,
        ) + timedelta(days=1)

        start_utc = start_local_dt.astimezone(timezone.utc).replace(tzinfo=None)
        end_utc = end_local_dt.astimezone(timezone.utc).replace(tzinfo=None)

        cursor = db.meals.find(
            {
                "user_id": user_id,
                "created_at": {"$gte": start_utc, "$lt": end_utc},
            },
            {"_id": 0, "macro_ratio": 1, "nutrition_level": 1, "created_at": 1, "meal_time": 1},
        )
        docs = await cursor.to_list(length=None)

        # Bucket by local-calendar date (preferring meal_time when present).
        buckets: dict[str, list[int]] = {}
        for doc in docs:
            anchor = doc.get("meal_time") or doc.get("created_at")
            if isinstance(anchor, str):
                try:
                    anchor = datetime.fromisoformat(anchor.replace("Z", ""))
                except ValueError:
                    anchor = doc.get("created_at")
            if not isinstance(anchor, datetime):
                continue
            if anchor.tzinfo is None:
                anchor = anchor.replace(tzinfo=timezone.utc)
            local_date = anchor.astimezone(zone).date().isoformat()

            level_value = doc.get("nutrition_level")
            score = self._nutrition_level_score(level_value)
            if score is None:
                # Legacy meal — derive on the fly using the recalibrated rules
                # (processing + added sugar are read off the doc when present).
                score = self._nutrition_level_score(
                    self._derive_nutrition_level(
                        doc.get("macro_ratio", {}),
                        processing_level=doc.get("processing_level"),
                        added_sugar=doc.get("added_sugar"),
                    ).value
                ) or 2
            buckets.setdefault(local_date, []).append(score)

        # Emit one entry per requested day, oldest first, including empty days.
        days_out: list[MealTrendDay] = []
        for offset in range(days):
            day_date = (start_local_date + timedelta(days=offset)).isoformat()
            scores = buckets.get(day_date, [])
            if scores:
                avg = sum(scores) / len(scores)
                days_out.append(MealTrendDay(
                    date=day_date,
                    level=self._nutrition_level_from_score(avg),
                    meal_count=len(scores),
                ))
            else:
                days_out.append(MealTrendDay(date=day_date, level=None, meal_count=0))

        return MealTrendResponse(days=days_out)

    # ============ Corrections ============

    async def save_correction(
        self,
        meal_id: str,
        user_id: str,
        data: MealCorrectionCreate,
    ) -> MealCorrectionResponse:
        db = get_database()
        meal = await db.meals.find_one({"meal_id": meal_id})
        if not meal:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Meal not found")
        if meal["user_id"] != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only the meal owner can submit corrections",
            )

        now = datetime.utcnow()
        doc = {
            "correction_id": str(uuid.uuid4()),
            "meal_id": meal_id,
            "user_id": user_id,
            "image_paths": [img.get("path") for img in meal.get("images", []) if img.get("path")],
            "original_food_items": [fi.model_dump() for fi in data.original_food_items],
            "corrected_food_items": [fi.model_dump() for fi in data.corrected_food_items],
            "original_macro_ratio": data.original_macro_ratio.model_dump() if data.original_macro_ratio else None,
            "corrected_macro_ratio": data.corrected_macro_ratio.model_dump() if data.corrected_macro_ratio else None,
            "created_at": now,
        }
        await db.meal_corrections.insert_one(doc)
        # A correction is a deliberate user edit — protect this meal from
        # future bridge syncs that would otherwise overwrite the user's input.
        await db.meals.update_one(
            {"meal_id": meal_id},
            {"$set": {"user_edited": True, "updated_at": now}},
        )
        return MealCorrectionResponse(
            correction_id=doc["correction_id"],
            meal_id=meal_id,
            user_id=user_id,
            created_at=format_utc_datetime(now),
        )

    # ============ Bridge: Nutrition Task → Meal ============

    @staticmethod
    def _nutrition_task_source_filter(task: dict) -> dict:
        return {
            "source_type": "nutrition_task",
            "source_task_id": task.get("task_id"),
            "user_id": task.get("user_id"),
        }

    @staticmethod
    def _meal_age_key(meal: dict):
        """Order key used to pick the canonical meal among duplicates.

        Oldest created_at wins; meal_time breaks ties. None values sort last
        so a malformed legacy doc never trumps a properly-stamped one.
        """
        created = meal.get("created_at")
        meal_time = meal.get("meal_time")
        if isinstance(meal_time, str):
            try:
                meal_time = datetime.fromisoformat(meal_time.replace("Z", ""))
            except ValueError:
                meal_time = None
        return (
            created is None,
            created or datetime.max,
            meal_time is None,
            meal_time or datetime.max,
        )

    async def _consolidate_duplicate_source_meals(
        self,
        db,
        candidates: List[dict],
    ) -> Optional[dict]:
        """Pick a canonical meal from a list of duplicates and remove the rest.

        Canonical = oldest created_at (so the original logged time is preserved).
        Drops the duplicates from `meals` and rewrites `dayprints.events.*`
        references to point at the canonical meal_id, keeping every connected
        surface (Dayprint, team feed, task-linked meal, detail screen) on the
        same row.

        Returns the canonical meal dict, or None when `candidates` is empty.
        """
        if not candidates:
            return None
        if len(candidates) == 1:
            return candidates[0]

        ordered = sorted(candidates, key=self._meal_age_key)
        canonical = ordered[0]
        canonical_id = canonical.get("meal_id")
        if not canonical_id:
            return canonical

        # Merge richer data from duplicates onto the canonical BEFORE we
        # delete them. Critical for the "one card with picture, one without"
        # bug — the canonical is the oldest by created_at (preserves logged
        # time), but the photo / structured food data may live on a younger
        # bridge-written row. We lift the display row's payload onto the
        # canonical so the surviving row carries the complete user-visible
        # state. Display row = the one with images (= the bridge's view).
        merged_fields: dict = {}
        display = next((d for d in ordered if d.get("images")), canonical)
        if display.get("images") and not (canonical.get("images") or []):
            merged_fields["images"] = display["images"]
        if display.get("food_items") and not (canonical.get("food_items") or []):
            merged_fields["food_items"] = display["food_items"]
        if not canonical.get("note"):
            for dup in ordered[1:]:
                if dup.get("note"):
                    merged_fields["note"] = dup["note"]
                    break
        if not canonical.get("source_type"):
            merged_fields["source_type"] = "nutrition_task"
        if not canonical.get("source_task_id"):
            for dup in ordered[1:]:
                tid = dup.get("source_task_id") or dup.get("linked_task_id")
                if tid:
                    merged_fields["source_task_id"] = tid
                    break
        if merged_fields:
            try:
                await db.meals.update_one(
                    {"meal_id": canonical_id},
                    {"$set": merged_fields},
                )
                canonical.update(merged_fields)
                logger.info(
                    "Merged into canonical meal %s: %s",
                    canonical_id, list(merged_fields.keys()),
                )
            except Exception as exc:
                logger.warning(
                    "Failed to merge duplicate fields into canonical %s: %s",
                    canonical_id, exc,
                )

        for dup in ordered[1:]:
            dup_id = dup.get("meal_id")
            if not dup_id or dup_id == canonical_id:
                continue
            try:
                await db.meals.delete_one({"meal_id": dup_id})
            except Exception as exc:
                logger.warning(
                    "Failed to delete duplicate meal %s during consolidation: %s",
                    dup_id, exc,
                )
                continue
            try:
                await db.dayprints.update_many(
                    {"events.data.meal_id": dup_id},
                    {"$set": {
                        "events.$[evt].data.meal_id": canonical_id,
                    }},
                    array_filters=[{"evt.data.meal_id": dup_id}],
                )
            except Exception as exc:
                logger.warning(
                    "Failed to rewrite dayprint references %s→%s: %s",
                    dup_id, canonical_id, exc,
                )
            logger.info(
                "Consolidated duplicate meal %s into canonical %s",
                dup_id, canonical_id,
            )
        return canonical

    async def _find_existing_nutrition_task_meal(self, db, task: dict) -> Optional[dict]:
        task_id = task.get("task_id")
        source_filter = self._nutrition_task_source_filter(task)
        cursor = db.meals.find({
            "$or": [
                source_filter,
                {"linked_task_id": task_id, "user_id": task.get("user_id")},
            ]
        })
        candidates = await cursor.to_list(length=None)
        existing = await self._consolidate_duplicate_source_meals(db, candidates)
        if existing and existing.get("source_type") != "nutrition_task":
            try:
                await db.meals.update_one(
                    {"meal_id": existing["meal_id"]},
                    {"$set": {
                        **source_filter,
                        "linked_task_id": task_id,
                    }},
                )
                existing.update(source_filter)
                existing["linked_task_id"] = task_id
            except DuplicateKeyError:
                existing = await db.meals.find_one(source_filter)
        return existing

    async def _log_bridged_meal_once(self, db, meal: dict) -> None:
        """Sync the dayprint event for a bridged meal.

        The dayprint layer is now idempotent on canonical source_key, so
        every bridge call (create / updateNote / uploadAttachments /
        completeTask / re-analysis) safely upserts the same one event —
        food_preview / image refresh, no duplicates.
        """
        meal_id = meal.get("meal_id")
        if not meal_id:
            return

        images = meal.get("images") or []
        first_image_url = images[0].get("url") if images else None
        await log_meal_logged(
            user_id=meal["user_id"],
            meal_id=meal_id,
            food_preview=self._food_preview(meal.get("food_items") or []),
            image_url=first_image_url,
            visibility=meal.get("visibility") or MealVisibility.PRIVATE.value,
            team_id=meal.get("team_id"),
            source_type="nutrition_task",
            source_task_id=meal.get("source_task_id") or meal.get("linked_task_id"),
        )

    async def create_meal_from_nutrition_task(
        self,
        task: dict,
        *,
        emit_dayprint: bool = False,
    ) -> Optional[str]:
        """Upsert a Meal record from a Nutrition task.

        Called from every Med-Reminder lifecycle event (create / update / note
        change / attachments upload / completion) so the Meals feature stays in
        sync with the source task automatically — the user never has to enter
        the same meal twice.

        Sync rules:
          • Look up an existing meal by stable source fields, with
            `linked_task_id` as a legacy fallback.
          • If the user has manually edited that meal in the Meals feature
            (`user_edited == True`), DO NOT overwrite — return the existing id.
          • Otherwise upsert: rebuild food_items / macro_ratio from the latest
            note via LLM (skipping the call when the note hash hasn't changed),
            and refresh images / team_id / visibility from the task.
          • If the task has no usable note AND no image attachments yet, skip
            (we don't bridge empty stubs).

        Returns the meal_id (existing or newly created), or None if there was
        nothing meaningful to bridge yet.
        """
        if not task:
            return None

        db = get_database()
        source_filter = self._nutrition_task_source_filter(task)
        existing = await self._find_existing_nutrition_task_meal(db, task)

        # Respect manual user edits — once the user touches the meal in the
        # Meals feature, the bridge stops overwriting it.
        if existing and existing.get("user_edited"):
            if emit_dayprint:
                try:
                    await self._log_bridged_meal_once(db, existing)
                except Exception as exc:
                    logger.warning(
                        "Dayprint log_meal_logged failed for bridged meal %s: %s",
                        existing.get("meal_id"), exc,
                    )
            return existing["meal_id"]

        attachments = [
            a for a in task.get("attachments", [])
            if (a.get("content_type") or "").startswith("image/")
        ]
        note = (task.get("note") or "").strip()
        if not attachments and not note:
            # Nothing meaningful to bridge yet. Don't create an empty stub.
            # If a stub already exists somehow, leave it alone.
            return existing["meal_id"] if existing else None

        # Skip the LLM call when the note text hasn't changed since the last
        # bridge run — common case on attachment upload, team reassignment, etc.
        note_hash = (
            hashlib.sha256(note.encode("utf-8")).hexdigest()[:16] if note else ""
        )
        reuse_structured = (
            existing is not None
            and existing.get("bridge_note_hash") == note_hash
            and existing.get("food_items")
        )

        if reuse_structured:
            structured = {
                "food_items": existing.get("food_items", []),
                "macro_ratio": existing.get("macro_ratio") or {
                    "protein": "moderate",
                    "carbs": "moderate",
                    "fat": "moderate",
                    "fiber": "low",
                },
            }
        else:
            try:
                structured = await self._structure_text_to_meal(
                    note, user_id=task.get("user_id"),
                ) if note else {
                    "food_items": [],
                    "macro_ratio": {
                        "protein": "moderate",
                        "carbs": "moderate",
                        "fat": "moderate",
                        "fiber": "low",
                    },
                }
            except Exception as exc:
                logger.warning(
                    "Bridge text→meal failed for task %s: %s",
                    task.get("task_id"), exc,
                )
                return existing["meal_id"] if existing else None

        if not structured["food_items"] and not attachments:
            return existing["meal_id"] if existing else None

        # Placeholder when LLM returned no items but we have images.
        if not structured["food_items"]:
            structured["food_items"] = [
                {"name": "Meal", "macro_ratio": structured["macro_ratio"]}
            ]

        # Mirror task attachments (metadata only; bytes stay under tasks/).
        images = [
            {
                "attachment_id": a.get("attachment_id") or str(uuid.uuid4()),
                "filename": a.get("filename"),
                "content_type": a.get("content_type", "image/jpeg"),
                "size_bytes": a.get("size_bytes", 0),
                "path": a.get("path"),
                "url": a.get("url"),
                "thumbnail_path": a.get("thumbnail_path"),
                "thumbnail_url": a.get("thumbnail_url"),
                "uploaded_at": a.get("uploaded_at"),
            }
            for a in attachments
        ]

        team_id = task.get("team_id")
        visibility = (
            MealVisibility.TEAM.value if team_id else MealVisibility.PRIVATE.value
        )
        now = datetime.utcnow()

        # v2 fields — prefer LLM output, fall back to deterministic helpers.
        # processing_level / added_sugar are computed first so the
        # recalibrated nutrition_level fallback can read them.
        meal_name = (structured.get("meal_name") or "").strip() or self._derive_meal_name_from_items(structured["food_items"])
        advisor_insight_value = (structured.get("advisor_insight") or "").strip() or None
        processing_level_value = structured.get("processing_level") or MacroLevel.MODERATE.value
        added_sugar_value = structured.get("added_sugar") or MacroLevel.LOW.value
        nutrition_level_value = structured.get("nutrition_level") or self._derive_nutrition_level(
            structured["macro_ratio"],
            processing_level=processing_level_value,
            added_sugar=added_sugar_value,
        ).value

        # meal_type / meal_time anchor on the user's local time, derived from
        # the task's open_datetime (when they planned to eat) if available,
        # else now.
        anchor_dt = self._parse_task_local_dt(task) or now
        try:
            tz_name = await self._resolve_user_timezone(task["user_id"])
            local_dt = anchor_dt if anchor_dt.tzinfo else anchor_dt.replace(tzinfo=timezone.utc)
            local_dt = local_dt.astimezone(self._safe_zone(tz_name))
            meal_type_value = self._derive_meal_type_from_local_dt(local_dt).value
        except Exception:
            meal_type_value = self._derive_meal_type_from_local_dt(anchor_dt).value
        meal_time_value = format_utc_datetime(anchor_dt if not anchor_dt.tzinfo else anchor_dt.astimezone(timezone.utc).replace(tzinfo=None))

        update_fields = {
            **source_filter,
            "linked_task_id": task.get("task_id"),
            "images": images,
            "food_items": structured["food_items"],
            "macro_ratio": structured["macro_ratio"],
            "note": note or None,
            "visibility": visibility,
            "team_id": team_id,
            "meal_name": meal_name,
            "nutrition_level": nutrition_level_value,
            "advisor_insight": advisor_insight_value,
            "processing_level": processing_level_value,
            "added_sugar": added_sugar_value,
            "bridge_note_hash": note_hash,
            "updated_at": now,
        }

        if existing:
            await db.meals.update_one(
                {"meal_id": existing["meal_id"]},
                {"$set": update_fields},
            )
            updated_meal = await db.meals.find_one({"meal_id": existing["meal_id"]})
            logger.info(
                "Bridge-updated nutrition task %s → meal %s",
                task.get("task_id"), existing["meal_id"],
            )
            if emit_dayprint and updated_meal:
                try:
                    await self._log_bridged_meal_once(db, updated_meal)
                except Exception as exc:
                    logger.warning(
                        "Dayprint log_meal_logged failed for bridged meal %s: %s",
                        existing["meal_id"], exc,
                    )
            return existing["meal_id"]

        meal_id = str(uuid.uuid4())
        insert_fields = {
            "meal_id": meal_id,
            "user_edited": False,
            "meal_type": meal_type_value,
            "meal_time": meal_time_value,
            "created_at": now,
        }
        try:
            result = await db.meals.update_one(
                source_filter,
                {
                    "$set": update_fields,
                    "$setOnInsert": insert_fields,
                },
                upsert=True,
            )
        except DuplicateKeyError:
            result = None

        meal = await db.meals.find_one(source_filter)
        if not meal:
            meal = await self._find_existing_nutrition_task_meal(db, task)
        if not meal:
            logger.warning(
                "Bridge could not resolve upserted nutrition task meal for %s",
                task.get("task_id"),
            )
            return None

        logger.info(
            "Bridge-%s nutrition task %s → meal %s",
            "created" if getattr(result, "upserted_id", None) is not None else "updated",
            task.get("task_id"), meal["meal_id"],
        )
        if emit_dayprint:
            try:
                await self._log_bridged_meal_once(db, meal)
            except Exception as exc:
                logger.warning(
                    "Dayprint log_meal_logged failed for bridged meal %s: %s",
                    meal.get("meal_id"), exc,
                )
        return meal["meal_id"]

    async def _build_history_context(self, user_id: str) -> Optional[str]:
        """Compact 14-day-history summary, injected into the structuring prompt
        so the LLM can shape advisor_insight tone and gently context-shift
        nutrition_level (Slice 7A §6 + §8). Returns None when the user has no
        recent meals — caller falls back to single-meal analysis.
        """
        try:
            db = get_database()
            cutoff = datetime.utcnow() - timedelta(days=14)
            cursor = db.meals.find(
                {"user_id": user_id, "created_at": {"$gte": cutoff}},
                {
                    "_id": 0,
                    "nutrition_level": 1,
                    "processing_level": 1,
                    "added_sugar": 1,
                },
            )
            docs = await cursor.to_list(length=None)
            if not docs:
                return None

            counts = {"Limited": 0, "Fair": 0, "Good": 0, "Nutritious": 0}
            high_processing = 0
            high_sugar = 0
            for doc in docs:
                lvl = doc.get("nutrition_level")
                if lvl in counts:
                    counts[lvl] += 1
                if doc.get("processing_level") == "high":
                    high_processing += 1
                if doc.get("added_sugar") == "high":
                    high_sugar += 1

            return (
                "USER'S LAST 14 DAYS — use this to shape advisor_insight tone "
                "and to slightly context-shift this meal's nutrition_level "
                "(a one-off treat in a balanced history should NOT be Limited):\n"
                f"  Total meals logged: {len(docs)}\n"
                f"  Nutritious: {counts['Nutritious']}, "
                f"Good: {counts['Good']}, "
                f"Fair: {counts['Fair']}, "
                f"Limited: {counts['Limited']}\n"
                f"  Meals with high processing level: {high_processing}\n"
                f"  Meals with high added sugar: {high_sugar}"
            )
        except Exception as exc:
            logger.warning(
                "Failed to build 14-day history for %s: %s", user_id, exc,
            )
            return None

    async def _structure_text_to_meal(
        self,
        text: str,
        user_id: Optional[str] = None,
    ) -> dict:
        """LLM call: convert nutrition note text → {food_items, macro_ratio,
        meal_name, nutrition_level, advisor_insight}.

        Per CLAUDE.md, semantic judgment (categorizing macro levels) is delegated
        to the LLM rather than hardcoded thresholds.

        Step 8 (correction learning): when `user_id` is provided, the user's
        last 5 stored corrections are injected as soft few-shot bias hints so
        the system adapts its predictions for that user personally over time.
        The base nutrition vision prompt itself stays unchanged (per Step 4) —
        the corrections live in this separate post-vision structuring call.
        """
        logger.info(
            "Structure ENTRY user_id=%s text_len=%d snippet=%r",
            user_id, len(text or ""), (text or "")[:120],
        )
        correction_hint = ""
        history_block = ""
        if user_id:
            try:
                correction_hint = await self._load_correction_hints(user_id)
                logger.info(
                    "Structure correction_hint_len=%d", len(correction_hint),
                )
            except Exception as exc:
                logger.warning("Failed to load correction hints for %s: %s", user_id, exc)
                correction_hint = ""
            history_context = await self._build_history_context(user_id)
            if history_context:
                history_block = f"\n\n{history_context}\n"
                logger.info(
                    "Structure 14-day history injected len=%d",
                    len(history_context),
                )

        system = (
            "You convert a short food description into structured meal data. "
            f"{_MACRO_CALIBRATION} "
            "Produce these meal-level fields: "
            "meal_name (3–6 word descriptive title, no diet language), "
            "nutrition_level (one of 'Limited' | 'Fair' | 'Good' | 'Nutritious'), "
            "processing_level (low | moderate | high — low=whole foods like raw "
            "vegetables, plain meat, eggs; moderate=lightly cooked or seasoned; "
            "high=packaged, fast food, or ultra-processed items), "
            "added_sugar (low | moderate | high — low=no added sugar (natural "
            "sugar in fruit does NOT count); moderate=lightly sweetened; "
            "high=heavily sweetened like desserts, sodas, candy), "
            "advisor_insight (1–2 short sentences, curious/observational tone, "
            "never judgmental, never numeric). "
            "\n\nADVISOR TONE RULES:\n"
            "- One-off treat in an otherwise balanced 2-week history: warm, "
            "permissive, celebratory. Example: \"A sweet treat every now and "
            "then is completely fine — you've been nourishing yourself really "
            "well\".\n"
            "- Occasional processed meal in a good history: light and gentle. "
            "Example: \"A little convenience food here and there is part of "
            "real life — aim to balance it out with some whole foods when you "
            "can\".\n"
            "- Frequent processed or high-added-sugar meals over the past 14 "
            "days: warm but direct. Example: \"You've been reaching for "
            "processed foods quite a bit lately — your body would really "
            "benefit from some more whole, nourishing meals this week\".\n"
            "- Consistently nutritious history: celebrate it. Example: "
            "\"You've been fuelling yourself really well — keep it up\".\n"
            "- Few or no recent meals: analyse this single meal only, no "
            "historical framing.\n"
            "\nNUTRITION LEVEL GRADING — be PERMISSIVE, not punishing.\n"
            "A meal does NOT need to be perfect to be Nutritious. Default "
            "UPWARD: any meal that is reasonably balanced AND minimally "
            "processed should be scored Nutritious. Reserve lower scores for "
            "meals that are genuinely imbalanced or heavily processed — not "
            "for meals that are simply imperfect.\n"
            "\n"
            "  • NUTRITIOUS: balanced whole-food meals (protein + vegetables "
            "+ whole grain or complex carb); natural nut butters with NO "
            "added sugar on whole-wheat / wholegrain bread; any meal that is "
            "minimally processed with reasonable macro balance. The "
            "following examples MUST score Nutritious: salmon with cabbage "
            "and jasmine rice; whole-wheat toast with natural peanut butter "
            "or almond butter; eggs with vegetables; oats with fruit; Greek "
            "yogurt bowl with whole ingredients.\n"
            "  • GOOD: mostly whole-food but slightly less balanced — e.g. "
            "missing a vegetable component, or using a refined grain "
            "alongside otherwise healthy ingredients. A light snack that is "
            "NOT ultra-processed (fruit, a handful of nuts, plain crackers).\n"
            "  • FAIR: meals with some processed elements but not "
            "predominantly ultra-processed. Natural nut butter on WHITE "
            "bread (whole-food spread, less-optimal base). A snack that is "
            "moderately processed but occasional.\n"
            "  • LIMITED: ONLY for meals that are genuinely ultra-processed "
            "AND high in added sugar, OR heavily refined with very little "
            "nutritional value. White bread with sugary peanut butter. Fast "
            "food / highly processed snacks AS A REGULAR HABIT (this means "
            "the user's 14-day history shows a consistent pattern). NEVER "
            "assign Limited to a single snack or treat unless the 14-day "
            "history clearly supports it.\n"
            "\nA single indulgent meal in an otherwise nutritious 14-day "
            "history must NOT be scored Limited — context-shift upward.\n"
            "\nFORBIDDEN WORDS — never use any form of: bad, unhealthy, "
            "wrong, junk, guilty, cheat, failure, warning, avoid, restrict, "
            "or anything that could trigger food anxiety. Tone is always a "
            "supportive, knowledgeable friend.\n"
            "\nPORTION WEIGHTS — for each food item output a "
            "`portion_weight` integer (1, 2, 3, …) reflecting that item's "
            "relative share of the plate. Larger portion → larger integer. "
            "If the input text already contains explicit portion hints in "
            "the form 'name (portion N)', RESPECT those exactly — they are "
            "the user's deliberate adjustments. If no portion hints are "
            "present, estimate the portions from the text (e.g. \"a "
            "generous serving of rice\" → 3, \"a small side of cabbage\" → "
            "1). Single-item meals always get portion_weight 1.\n"
            "\nPORTION-AWARE MACRO WEIGHTING — the meal-level `macro_ratio` "
            "and `nutrition_level` MUST be weighted by each item's "
            "portion_weight. A small whole-food side does NOT pull a "
            "processed dominant item up; a dominant whole-food item DOES "
            "pull the meal up even if there's a small processed side. The "
            "advisor_insight should acknowledge this when relevant: if a "
            "whole-food item dominates, highlight that positively; if a "
            "less nutritious item dominates after user adjustment, gently "
            "note the balance and suggest keeping whole-food portions "
            "generous — never judgmental, never use forbidden words."
            f"{history_block}"
            "\nOutput strict JSON only matching this schema: "
            '{"food_items":[{"name":"string","portion_weight":1,"macro_ratio":{"protein":"low|moderate|high",'
            '"carbs":"low|moderate|high","fat":"low|moderate|high","fiber":"low|moderate|high"}}],'
            '"macro_ratio":{"protein":"low|moderate|high","carbs":"low|moderate|high",'
            '"fat":"low|moderate|high","fiber":"low|moderate|high"},'
            '"meal_name":"string","nutrition_level":"Limited|Fair|Good|Nutritious",'
            '"processing_level":"low|moderate|high","added_sugar":"low|moderate|high",'
            '"advisor_insight":"string"}. '
            "Never include numbers, calories, or kcal in the output."
            f"{correction_hint}"
        )

        # Match the working Nutrition Task pipeline's provider order: call the
        # configured OpenAI endpoint directly first, then fall back to the shared
        # PaleBlueDot path only when OpenAI is unavailable or rejects the request.
        if settings.OPENAI_API_KEY:
            url = f"{settings.OPENAI_API_BASE_URL.rstrip('/')}/chat/completions"
            payload = {
                "model": settings.OPENAI_VISION_MODEL,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": text},
                ],
                "max_tokens": 400,
                "temperature": 0.1,
                "response_format": {"type": "json_object"},
            }
            headers = {
                "Authorization": f"Bearer {settings.OPENAI_API_KEY}",
                "Content-Type": "application/json",
            }
            logger.info(
                "Structure OpenAI request model=%s url=%s text_len=%d",
                payload["model"], url, len(text or ""),
            )
            try:
                async with httpx.AsyncClient(timeout=120.0) as client:
                    resp = await client.post(url, headers=headers, json=payload)
                logger.info(
                    "Structure OpenAI response status=%s", resp.status_code,
                )
                if resp.status_code < 400:
                    data = resp.json()
                    msg = ((data.get("choices") or [{}])[0] or {}).get("message") or {}
                    raw = msg.get("content")
                    if isinstance(raw, str) and raw.strip():
                        parsed = self._parse_analysis_json(raw)
                        logger.info(
                            "Structure OpenAI OK food_items=%d via=str",
                            len(parsed.get("food_items", [])),
                        )
                        return parsed
                    if isinstance(raw, list):
                        joined = " ".join(
                            item.get("text", "")
                            for item in raw
                            if isinstance(item, dict)
                            and isinstance(item.get("text"), str)
                        )
                        if joined.strip():
                            parsed = self._parse_analysis_json(joined)
                            logger.info(
                                "Structure OpenAI OK food_items=%d via=list",
                                len(parsed.get("food_items", [])),
                            )
                            return parsed
                    logger.warning(
                        "Structure OpenAI returned 2xx but no usable content "
                        "(raw=%r)", raw,
                    )
                else:
                    logger.warning(
                        "OpenAI meal text structuring failed: status=%s body=%s",
                        resp.status_code,
                        resp.text[:500],
                    )
            except Exception as exc:
                logger.warning("OpenAI meal text structuring raised: %s", exc)

        logger.info("Structure falling back to PaleBlueDot")
        response = await chat_completion(
            messages=[{"role": "user", "content": text}],
            system=system,
            max_tokens=400,
            temperature=0.1,
        )
        parsed = self._parse_analysis_json(response.text or "")
        logger.info(
            "Structure PaleBlueDot result food_items=%d",
            len(parsed.get("food_items", [])),
        )
        return parsed


meal_service = MealService()
