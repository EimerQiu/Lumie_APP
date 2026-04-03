"""Skill Registry Service — scans, parses, indexes, and retrieves skill .md files.

Skills are stored as repository .md files with YAML frontmatter.
This service builds an in-memory index at startup and supports top-k retrieval.
"""
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml

logger = logging.getLogger(__name__)

# ── Skill directory ──────────────────────────────────────────────────────────

SKILLS_DIR = Path(__file__).parent.parent / "skills"

# ── Required frontmatter fields ──────────────────────────────────────────────

REQUIRED_FIELDS = {
    "skill_id", "title", "capability_id", "runtime_type",
    "requires_ping", "requires_credentials", "target_system", "summary",
}


# ── Data structures ──────────────────────────────────────────────────────────

@dataclass
class SkillIndexItem:
    skill_id: str
    title: str
    capability_id: str
    runtime_type: str
    requires_ping: bool
    requires_credentials: bool
    target_system: str
    summary: str
    tags: list[str] = field(default_factory=list)
    keywords: list[str] = field(default_factory=list)
    allowed_connectors: list[str] = field(default_factory=list)
    api_endpoint: Optional[str] = None
    api_method: str = "GET"
    shared_credential_id: Optional[str] = None
    credential_display_name: Optional[str] = None
    # Proactive metadata
    proactive_eligible: bool = False
    proactive_domain: Optional[str] = None   # sleep|activity|medication|recovery|dayprint|team_followup|decision
    proactive_priority: int = 0
    proactive_mode: Optional[str] = None     # assessment|decision
    status: str = "indexed"
    file_path: str = ""
    last_error: Optional[str] = None


class SkillRegistry:
    """In-memory skill index built from repository .md files."""

    def __init__(self) -> None:
        # Primary index: skill_id -> SkillIndexItem
        self.skills_by_id: dict[str, SkillIndexItem] = {}
        # Capability index: capability_id -> set(skill_id)
        self.skills_by_capability: dict[str, set[str]] = {}
        # Inverted index: term -> set(skill_id)
        self.inverted_index: dict[str, set[str]] = {}
        self._scanned = False

    def scan_and_index(self) -> dict:
        """Scan all .md files under SKILLS_DIR, parse frontmatter, build indexes.

        Returns a summary dict with counts.
        """
        self.skills_by_id.clear()
        self.skills_by_capability.clear()
        self.inverted_index.clear()

        if not SKILLS_DIR.exists():
            logger.warning(f"Skills directory not found: {SKILLS_DIR}")
            self._scanned = True
            return {"total": 0, "indexed": 0, "invalid": 0}

        md_files = list(SKILLS_DIR.rglob("*.md"))
        indexed = 0
        invalid = 0

        for fpath in md_files:
            try:
                item = self._parse_skill_file(fpath)
                if item.status == "indexed":
                    self._add_to_index(item)
                    indexed += 1
                else:
                    invalid += 1
            except Exception as e:
                logger.warning(f"Failed to parse skill file {fpath}: {e}")
                invalid += 1

        self._scanned = True
        logger.info(f"Skill registry: {indexed} indexed, {invalid} invalid, {len(md_files)} total files")
        return {"total": len(md_files), "indexed": indexed, "invalid": invalid}

    def _parse_skill_file(self, fpath: Path) -> SkillIndexItem:
        """Parse a single skill .md file and return a SkillIndexItem."""
        text = fpath.read_text(encoding="utf-8")

        # Extract YAML frontmatter between --- markers
        match = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
        if not match:
            return SkillIndexItem(
                skill_id=fpath.stem,
                title=fpath.stem,
                capability_id="",
                runtime_type="",
                requires_ping=False,
                requires_credentials=False,
                target_system="",
                summary="",
                status="invalid_frontmatter",
                file_path=str(fpath),
                last_error="No frontmatter found",
            )

        try:
            fm = yaml.safe_load(match.group(1))
        except yaml.YAMLError as e:
            return SkillIndexItem(
                skill_id=fpath.stem,
                title=fpath.stem,
                capability_id="",
                runtime_type="",
                requires_ping=False,
                requires_credentials=False,
                target_system="",
                summary="",
                status="invalid_frontmatter",
                file_path=str(fpath),
                last_error=f"YAML parse error: {e}",
            )

        # Validate required fields
        missing = REQUIRED_FIELDS - set(fm.keys())
        if missing:
            return SkillIndexItem(
                skill_id=fm.get("skill_id", fpath.stem),
                title=fm.get("title", fpath.stem),
                capability_id=fm.get("capability_id", ""),
                runtime_type=fm.get("runtime_type", ""),
                requires_ping=fm.get("requires_ping", False),
                requires_credentials=fm.get("requires_credentials", False),
                target_system=fm.get("target_system", ""),
                summary=fm.get("summary", ""),
                status="invalid_frontmatter",
                file_path=str(fpath),
                last_error=f"Missing fields: {missing}",
            )

        tags = fm.get("tags", [])
        if isinstance(tags, str):
            tags = [t.strip() for t in tags.split(",")]
        keywords = fm.get("keywords", [])
        if isinstance(keywords, str):
            keywords = [k.strip() for k in keywords.split(",")]

        return SkillIndexItem(
            skill_id=fm["skill_id"],
            title=fm["title"],
            capability_id=fm["capability_id"],
            runtime_type=fm["runtime_type"],
            requires_ping=bool(fm["requires_ping"]),
            requires_credentials=bool(fm["requires_credentials"]),
            target_system=fm["target_system"],
            summary=fm["summary"],
            tags=tags,
            keywords=keywords,
            allowed_connectors=fm.get("allowed_connectors", []),
            api_endpoint=fm.get("api_endpoint"),
            api_method=fm.get("api_method", "GET").upper(),
            shared_credential_id=fm.get("shared_credential_id"),
            credential_display_name=fm.get("credential_display_name"),
            proactive_eligible=bool(fm.get("proactive_eligible", False)),
            proactive_domain=fm.get("proactive_domain"),
            proactive_priority=int(fm.get("proactive_priority", 0)),
            proactive_mode=fm.get("proactive_mode"),
            status="indexed",
            file_path=str(fpath),
        )

    def _add_to_index(self, item: SkillIndexItem) -> None:
        """Add a parsed skill to all index layers."""
        sid = item.skill_id

        # 1. Primary index
        self.skills_by_id[sid] = item

        # 2. Capability index
        self.skills_by_capability.setdefault(item.capability_id, set()).add(sid)

        # 3. Inverted index from title, summary, tags, keywords
        terms = set()
        terms.update(self._tokenize(item.title))
        terms.update(self._tokenize(item.summary))
        for tag in item.tags:
            terms.update(self._tokenize(tag))
        for kw in item.keywords:
            terms.update(self._tokenize(kw))

        for term in terms:
            self.inverted_index.setdefault(term, set()).add(sid)

    @staticmethod
    def _tokenize(text: str) -> set[str]:
        """Simple whitespace + lowercase tokenizer."""
        return {w.lower() for w in re.findall(r"\w+", text) if len(w) > 1}

    # ── Retrieval ────────────────────────────────────────────────────────────

    def retrieve_top_k(
        self,
        query: str,
        enabled_capabilities: set[str],
        top_k: int = 8,
    ) -> list[SkillIndexItem]:
        """Retrieve the top-k most relevant skills for a user query.

        Only returns skills whose capability is in `enabled_capabilities`
        and whose status is 'indexed'.
        """
        if not self._scanned:
            self.scan_and_index()

        query_terms = self._tokenize(query)
        if not query_terms:
            # No meaningful terms — return all enabled skills up to top_k
            return self._all_enabled_skills(enabled_capabilities)[:top_k]

        # Score each skill by keyword hit count
        scores: dict[str, float] = {}
        for term in query_terms:
            matching_sids = self.inverted_index.get(term, set())
            for sid in matching_sids:
                item = self.skills_by_id.get(sid)
                if not item or item.status != "indexed":
                    continue
                if item.capability_id not in enabled_capabilities:
                    continue

                # Weight: keywords > tags > title/summary
                weight = 1.0
                term_lower = term.lower()
                if any(term_lower in self._tokenize(kw) for kw in item.keywords):
                    weight = 3.0
                elif any(term_lower in self._tokenize(tag) for tag in item.tags):
                    weight = 2.0

                scores[sid] = scores.get(sid, 0) + weight

        # Sort by score descending
        ranked = sorted(scores.keys(), key=lambda s: scores[s], reverse=True)

        # If we have fewer than top_k results, pad with other enabled skills
        result_ids = ranked[:top_k]
        if len(result_ids) < top_k:
            for item in self._all_enabled_skills(enabled_capabilities):
                if item.skill_id not in result_ids:
                    result_ids.append(item.skill_id)
                if len(result_ids) >= top_k:
                    break

        return [self.skills_by_id[sid] for sid in result_ids if sid in self.skills_by_id]

    def _all_enabled_skills(self, enabled_capabilities: set[str]) -> list[SkillIndexItem]:
        """Return all indexed skills for enabled capabilities."""
        return [
            item for item in self.skills_by_id.values()
            if item.status == "indexed" and item.capability_id in enabled_capabilities
        ]

    # ── Direct lookups ───────────────────────────────────────────────────────

    def get_skill(self, skill_id: str) -> Optional[SkillIndexItem]:
        """Get a skill by ID."""
        return self.skills_by_id.get(skill_id)

    def get_skills_by_capability(self, capability_id: str) -> list[SkillIndexItem]:
        """Get all indexed skills for a capability."""
        sids = self.skills_by_capability.get(capability_id, set())
        return [self.skills_by_id[sid] for sid in sids if self.skills_by_id[sid].status == "indexed"]

    def get_all_skills(self) -> list[SkillIndexItem]:
        """Get all skills (any status)."""
        return list(self.skills_by_id.values())

    def get_proactive_skills(self) -> list[SkillIndexItem]:
        """Get all proactive-eligible skills, sorted by priority (descending)."""
        if not self._scanned:
            self.scan_and_index()
        return sorted(
            [item for item in self.skills_by_id.values()
             if item.status == "indexed" and item.proactive_eligible],
            key=lambda x: x.proactive_priority,
            reverse=True,
        )

    def get_proactive_skills_for_capabilities(
        self, enabled_capabilities: set[str]
    ) -> list[SkillIndexItem]:
        """Get proactive-eligible skills filtered by enabled capabilities."""
        if not self._scanned:
            self.scan_and_index()
        return sorted(
            [item for item in self.skills_by_id.values()
             if item.status == "indexed"
             and item.proactive_eligible
             and item.capability_id in enabled_capabilities],
            key=lambda x: x.proactive_priority,
            reverse=True,
        )

    def get_proactive_skills_by_domain(self, domain: str) -> list[SkillIndexItem]:
        """Get proactive-eligible skills for a specific domain."""
        if not self._scanned:
            self.scan_and_index()
        return [
            item for item in self.skills_by_id.values()
            if item.status == "indexed"
            and item.proactive_eligible
            and item.proactive_domain == domain
        ]

    def load_skill_full_text(self, skill_id: str) -> Optional[str]:
        """Load the full .md file content for a selected skill."""
        item = self.skills_by_id.get(skill_id)
        if not item or not item.file_path:
            return None
        try:
            return Path(item.file_path).read_text(encoding="utf-8")
        except Exception as e:
            logger.error(f"Failed to read skill file {item.file_path}: {e}")
            return None


# ── Singleton ────────────────────────────────────────────────────────────────

skill_registry = SkillRegistry()
