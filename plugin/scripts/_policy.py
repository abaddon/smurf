"""Shared policy.yaml loader for the smurf Python scripts.

Single Python-side policy parser (the bash-side equivalent is
lib/policy.sh). PyYAML when available; otherwise a minimal fallback
parser that extracts just the `wiki:` block — the only section the
Python scripts consume.
"""

from __future__ import annotations

from pathlib import Path


def load_policy(project_root: Path, plugin_root: Path) -> dict:
    """Resolve the policy: project override wins, plugin default fallback."""
    for p in [project_root / ".claude" / "policy.yaml", plugin_root / "policy.yaml"]:
        if p.is_file():
            try:
                import yaml  # type: ignore
                return yaml.safe_load(p.read_text()) or {}
            except ImportError:
                return _minimal_yaml(p.read_text())
    return {}


def _minimal_yaml(text: str) -> dict:
    """Extract just the wiki: block without depending on PyYAML."""
    wiki: dict = {}
    in_wiki = False
    for raw in text.splitlines():
        if raw.startswith("wiki:"):
            in_wiki = True
            continue
        if in_wiki:
            if raw and not raw.startswith(("  ", "\t")):
                break
            if ":" in raw:
                k, _, v = raw.strip().partition(":")
                v = v.strip().strip('"').strip("'")
                if v.lower() in ("true", "false"):
                    wiki[k] = v.lower() == "true"
                elif v.isdigit():
                    wiki[k] = int(v)
                elif v:
                    wiki[k] = v
    return {"wiki": wiki} if wiki else {}
