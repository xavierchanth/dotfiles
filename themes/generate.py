#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Validate Clarity definitions and generate Ghostty themes and viewer data."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import webbrowser
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent
DEFINITIONS_DIR = ROOT / "definitions"
PROFILES_DIR = ROOT / "profiles"
GHOSTTY_DIR = ROOT.parent / "stow" / "ghostty-themes"
VIEWER_DATA = ROOT / "viewer" / "themes.generated.js"
SELECTION_FILE = ROOT / "selection.json"

COLOR_NAMES = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
HEX_COLOR = re.compile(r"^#[0-9a-f]{6}$")
THEME_ID = re.compile(r"^clarity-[a-z0-9]+(?:-[a-z0-9]+)*$")
APPEARANCES = ("light", "dark")

NVIM_GROUPS = (
    "Comment",
    "Keyword",
    "Statement",
    "Function",
    "String",
    "Type",
    "Constant",
    "Visual",
    "DiffAdd",
    "DiffChange",
    "DiffDelete",
    "Pmenu",
    "RenderMarkdownH1Bg",
    "RenderMarkdownH2Bg",
    "RenderMarkdownH3Bg",
    "RenderMarkdownH4Bg",
    "RenderMarkdownH5Bg",
    "RenderMarkdownH6Bg",
)


class ThemeError(Exception):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ThemeError(f"{path}: {error}") from error
    if not isinstance(value, dict):
        raise ThemeError(f"{path}: expected a JSON object")
    return value


def require_keys(
    value: dict[str, Any], required: set[str], allowed: set[str], context: str
) -> None:
    missing = sorted(required - value.keys())
    unknown = sorted(value.keys() - allowed)
    if missing:
        raise ThemeError(f"{context}: missing fields: {', '.join(missing)}")
    if unknown:
        raise ThemeError(f"{context}: unknown fields: {', '.join(unknown)}")


def require_color(value: Any, context: str) -> str:
    if not isinstance(value, str) or not HEX_COLOR.fullmatch(value):
        raise ThemeError(f"{context}: expected a lowercase six-digit hex color")
    return value


def validate_bank(value: Any, context: str) -> dict[str, str]:
    if not isinstance(value, dict):
        raise ThemeError(f"{context}: expected an object")
    expected = set(COLOR_NAMES)
    require_keys(value, expected, expected, context)
    return {
        name: require_color(value[name], f"{context}.{name}") for name in COLOR_NAMES
    }


def validate_theme(path: Path) -> dict[str, Any]:
    theme = read_json(path)
    required = {
        "schemaVersion",
        "id",
        "name",
        "appearance",
        "description",
        "ui",
        "palette",
    }
    allowed = required | {"$schema"}
    require_keys(theme, required, allowed, str(path))

    if theme["schemaVersion"] != 1:
        raise ThemeError(
            f"{path}: unsupported schemaVersion {theme['schemaVersion']!r}"
        )
    if not isinstance(theme["id"], str) or not THEME_ID.fullmatch(theme["id"]):
        raise ThemeError(f"{path}: invalid theme id {theme['id']!r}")
    if path.stem != theme["id"]:
        raise ThemeError(f"{path}: filename must match theme id {theme['id']!r}")
    if not isinstance(theme["name"], str) or not theme["name"].strip():
        raise ThemeError(f"{path}: name must be non-empty")
    if theme["appearance"] not in APPEARANCES:
        raise ThemeError(f"{path}: appearance must be light or dark")
    if not isinstance(theme["description"], str) or not theme["description"].strip():
        raise ThemeError(f"{path}: description must be non-empty")

    ui = theme["ui"]
    ui_keys = {
        "background",
        "foreground",
        "cursor",
        "selectionBackground",
        "selectionForeground",
    }
    if not isinstance(ui, dict):
        raise ThemeError(f"{path}.ui: expected an object")
    require_keys(ui, ui_keys, ui_keys, f"{path}.ui")
    theme["ui"] = {key: require_color(ui[key], f"{path}.ui.{key}") for key in ui_keys}

    palette = theme["palette"]
    if not isinstance(palette, dict):
        raise ThemeError(f"{path}.palette: expected an object")
    require_keys(palette, {"normal", "bright"}, {"normal", "bright"}, f"{path}.palette")
    theme["palette"] = {
        "normal": validate_bank(palette["normal"], f"{path}.palette.normal"),
        "bright": validate_bank(palette["bright"], f"{path}.palette.bright"),
    }
    theme.pop("$schema", None)
    return theme


def validate_selection(themes: list[dict[str, Any]]) -> dict[str, Any]:
    selection = read_json(SELECTION_FILE)
    required = {"schemaVersion", "light", "dark"}
    require_keys(selection, required, required, str(SELECTION_FILE))
    if selection["schemaVersion"] != 1:
        raise ThemeError(f"{SELECTION_FILE}: unsupported schemaVersion")
    by_id = {theme["id"]: theme for theme in themes}
    for appearance in APPEARANCES:
        selected = selection[appearance]
        if selected not in by_id:
            raise ThemeError(
                f"{SELECTION_FILE}: unknown {appearance} theme {selected!r}"
            )
        if by_id[selected]["appearance"] != appearance:
            raise ThemeError(
                f"{SELECTION_FILE}: {selected!r} is not a {appearance} theme"
            )
    return selection


def validate_profile(path: Path) -> dict[str, Any]:
    profile = read_json(path)
    common = {"schemaVersion", "application", "appearance", "label", "sourceTheme"}
    if profile.get("application") == "neovim":
        require_keys(profile, common | {"groups"}, common | {"groups"}, str(path))
        groups = profile["groups"]
        if not isinstance(groups, dict):
            raise ThemeError(f"{path}.groups: expected an object")
        require_keys(groups, set(NVIM_GROUPS), set(NVIM_GROUPS), f"{path}.groups")
        for group, spec in groups.items():
            if not isinstance(spec, dict):
                raise ThemeError(f"{path}.groups.{group}: expected an object")
            require_keys(
                spec,
                set(),
                {"foreground", "background", "styles"},
                f"{path}.groups.{group}",
            )
            if "foreground" not in spec and "background" not in spec:
                raise ThemeError(
                    f"{path}.groups.{group}: expected a foreground or background"
                )
            for field in ("foreground", "background"):
                if field in spec and (
                    not isinstance(spec[field], int) or not 0 <= spec[field] <= 15
                ):
                    raise ThemeError(
                        f"{path}.groups.{group}.{field}: expected an ANSI index from 0 to 15"
                    )
            if "styles" in spec and (
                not isinstance(spec["styles"], list)
                or not all(isinstance(style, str) for style in spec["styles"])
            ):
                raise ThemeError(
                    f"{path}.groups.{group}.styles: expected a string array"
                )
    else:
        raise ThemeError(f"{path}: application must be neovim")

    if profile.get("schemaVersion") != 1:
        raise ThemeError(f"{path}: unsupported schemaVersion")
    if profile.get("appearance") not in APPEARANCES:
        raise ThemeError(f"{path}: appearance must be light or dark")
    filename_app = (
        "nvim" if profile["application"] == "neovim" else profile["application"]
    )
    expected_name = f"{filename_app}-{profile['appearance']}.json"
    if path.name != expected_name:
        raise ThemeError(f"{path}: filename must be {expected_name}")
    return profile


def load_model() -> tuple[list[dict[str, Any]], dict[str, Any], list[dict[str, Any]]]:
    themes = [validate_theme(path) for path in sorted(DEFINITIONS_DIR.glob("*.json"))]
    if not themes:
        raise ThemeError(f"{DEFINITIONS_DIR}: no theme definitions found")
    ids = [theme["id"] for theme in themes]
    names = [theme["name"] for theme in themes]
    if len(ids) != len(set(ids)):
        raise ThemeError("theme ids must be unique")
    if len(names) != len(set(names)):
        raise ThemeError("theme names must be unique")
    selection = validate_selection(themes)
    profiles = [validate_profile(path) for path in sorted(PROFILES_DIR.glob("*.json"))]
    expected_profiles = {
        (app, appearance) for app in ("neovim",) for appearance in APPEARANCES
    }
    actual_profiles = {
        (profile["application"], profile["appearance"]) for profile in profiles
    }
    if actual_profiles != expected_profiles:
        raise ThemeError(
            "profiles must contain exactly one light and dark snapshot for Neovim"
        )
    return themes, selection, profiles


def palette_colors(theme: dict[str, Any]) -> list[str]:
    return [
        theme["palette"][bank][name]
        for bank in ("normal", "bright")
        for name in COLOR_NAMES
    ]


def ghostty_theme(theme: dict[str, Any]) -> str:
    ui = theme["ui"]
    lines = [
        f"background = {ui['background']}",
        f"cursor-color = {ui['cursor']}",
        f"foreground = {ui['foreground']}",
    ]
    lines.extend(
        f"palette = {index}={color}"
        for index, color in enumerate(palette_colors(theme))
    )
    lines.extend(
        (
            f"selection-background = {ui['selectionBackground']}",
            f"selection-foreground = {ui['selectionForeground']}",
        )
    )
    return "\n".join(lines) + "\n"


def expected_outputs() -> dict[Path, str]:
    themes, selection, profiles = load_model()
    outputs = {GHOSTTY_DIR / theme["id"]: ghostty_theme(theme) for theme in themes}
    data = {
        "schemaVersion": 1,
        "selection": {"light": selection["light"], "dark": selection["dark"]},
        "themes": [dict(theme, colors=palette_colors(theme)) for theme in themes],
        "profiles": profiles,
    }
    outputs[VIEWER_DATA] = (
        "window.CLARITY_THEME_DATA = "
        + json.dumps(data, indent=2, sort_keys=True, separators=(",", ": "))
        + ";\n"
    )
    return outputs


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w") as file:
            file.write(content)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def generate() -> None:
    outputs = expected_outputs()
    for path, content in outputs.items():
        atomic_write(path, content)
    expected_ghostty = {path.name for path in outputs if path.parent == GHOSTTY_DIR}
    if GHOSTTY_DIR.exists():
        for path in GHOSTTY_DIR.iterdir():
            if path.is_file() and path.name not in expected_ghostty:
                path.unlink()


def check() -> bool:
    outputs = expected_outputs()
    problems: list[str] = []
    for path, content in outputs.items():
        display_path = path.relative_to(ROOT.parent)
        if not path.exists():
            problems.append(f"missing: {display_path}")
        elif path.read_text() != content:
            problems.append(f"stale: {display_path}")
    expected_ghostty = {path.name for path in outputs if path.parent == GHOSTTY_DIR}
    if GHOSTTY_DIR.exists():
        for path in sorted(GHOSTTY_DIR.iterdir()):
            if path.is_file() and path.name not in expected_ghostty:
                problems.append(f"unexpected: {path.relative_to(ROOT.parent)}")
    if problems:
        print("Generated theme artifacts are not current:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return False
    return True


def parse_highlights(output: str, appearance: str) -> dict[str, Any]:
    records: dict[str, str] = {}
    current: str | None = None
    for line in output.splitlines():
        match = re.match(r"^(\S+)\s+xxx(?:\s+(.*))?$", line)
        if match:
            current = match.group(1)
            records[current] = match.group(2) or ""
        elif current is not None and line[:1].isspace():
            records[current] += " " + line.strip()
        else:
            current = None

    groups: dict[str, dict[str, Any]] = {}
    for group in NVIM_GROUPS:
        record = records.get(group)
        if record is None:
            raise ThemeError(f"Neovim :highlight output is missing {group}")
        spec: dict[str, Any] = {}
        foreground = re.search(r"(?:^|\s)ctermfg=(\d+)(?:\s|$)", record)
        background = re.search(r"(?:^|\s)ctermbg=(\d+)(?:\s|$)", record)
        styles = re.search(r"(?:^|\s)cterm=([^\s]+)", record)
        if foreground:
            spec["foreground"] = int(foreground.group(1))
        if background:
            spec["background"] = int(background.group(1))
        if styles and styles.group(1) != "NONE":
            spec["styles"] = styles.group(1).split(",")
        if "foreground" not in spec and "background" not in spec:
            raise ThemeError(
                f"Neovim highlight {group} has no numeric cterm color: {record}"
            )
        groups[group] = spec
    return {
        "schemaVersion": 1,
        "application": "neovim",
        "appearance": appearance,
        "label": f"Neovim ANSI {appearance}",
        "sourceTheme": "clarity-cterm",
        "groups": groups,
    }


def capture_nvim_profile(appearance: str, nvim: str) -> dict[str, Any]:
    command = [
        nvim,
        "--headless",
        f"+set background={appearance}",
        "+colorscheme clarity-cterm",
        "+highlight",
        "+qa!",
    ]
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode != 0:
        raise ThemeError(f"Neovim highlight capture failed:\n{result.stdout}")
    return parse_highlights(result.stdout, appearance)


def write_profile(profile: dict[str, Any]) -> None:
    filename_app = (
        "nvim" if profile["application"] == "neovim" else profile["application"]
    )
    path = PROFILES_DIR / f"{filename_app}-{profile['appearance']}.json"
    atomic_write(path, json.dumps(profile, indent=2, sort_keys=False) + "\n")


def refresh_profiles(nvim: str) -> None:
    for appearance in APPEARANCES:
        write_profile(capture_nvim_profile(appearance, nvim))
    generate()


def preview() -> None:
    if not check():
        raise ThemeError("generated artifacts are stale; run generate first")
    if not VIEWER_DATA.exists():
        raise ThemeError("viewer data is missing; run generate first")
    viewer = ROOT / "viewer" / "index.html"
    if not viewer.exists():
        raise ThemeError(f"viewer is missing: {viewer}")
    webbrowser.open(viewer.resolve().as_uri())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser(
        "generate", help="validate definitions and write generated artifacts"
    )
    subparsers.add_parser(
        "check", help="validate definitions and check generated artifacts"
    )
    refresh = subparsers.add_parser(
        "refresh-profiles", help="refresh committed Neovim snapshots"
    )
    refresh.add_argument("--nvim", default=shutil.which("nvim") or "nvim")
    subparsers.add_parser("preview", help="open the permanent theme viewer")
    args = parser.parse_args()

    try:
        command = args.command or "generate"
        if command == "generate":
            generate()
        elif command == "check":
            return 0 if check() else 1
        elif command == "refresh-profiles":
            refresh_profiles(args.nvim)
        elif command == "preview":
            preview()
    except ThemeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
