#!/usr/bin/env python3
"""
sync-ai: 공통 AI 설정 마스터(~/.agents/)의 MCP·스킬을
Antigravity(Gemini), Claude Code, Codex(GPT)로 동기화합니다.

로컬 머신별 워크스페이스 목록은 ~/.agents/sync-ai.json에 둘 수 있습니다:
  {
    "workspaces": ["~/path/to/workspace"]
  }
"""

import argparse
import json
import re
import shutil
from pathlib import Path

HOME = Path.home()
AGENTS_DIR = HOME / ".agents"
MASTER_MCP_PATH = AGENTS_DIR / "mcp.json"
SYNC_CONFIG_PATH = AGENTS_DIR / "sync-ai.json"

# Target config paths
AGY_CONFIG_DIR = HOME / ".gemini" / "config"
AGY_MCP_PATH = AGY_CONFIG_DIR / "mcp_config.json"
AGY_SKILLS_PATH = AGY_CONFIG_DIR / "skills.json"

CLAUDE_JSON_PATH = HOME / ".claude.json"
CLAUDE_SETTINGS_PATH = HOME / ".claude" / "settings.json"
CLAUDE_INSTALLED_PLUGINS_PATH = HOME / ".claude" / "plugins" / "installed_plugins.json"
CLAUDE_SKILLS_DIR = HOME / ".claude" / "skills"

CODEX_CONFIG_PATH = HOME / ".codex" / "config.toml"
CODEX_SKILLS_DIR = HOME / ".codex" / "skills"
AGENTS_SKILLS_DIR = AGENTS_DIR / "skills"

MANAGED_START = "# >>> sync-ai managed MCP >>>"
MANAGED_END = "# <<< sync-ai managed MCP <<<"


def load_workspaces(cli_workspaces: list[str] | None = None) -> list[Path]:
    raw: list[str] = []
    if SYNC_CONFIG_PATH.exists():
        try:
            cfg = json.loads(SYNC_CONFIG_PATH.read_text(encoding="utf-8"))
            raw.extend(cfg.get("workspaces", []))
        except Exception as e:
            print(f"[WARN] {SYNC_CONFIG_PATH} 읽기 실패: {e}")
    if cli_workspaces:
        raw.extend(cli_workspaces)

    seen = set()
    result = []
    for item in raw:
        p = Path(item).expanduser().resolve()
        if p not in seen and p.is_dir():
            seen.add(p)
            result.append(p)
    return result


def clean_server_entry(entry: dict, for_tool: str) -> dict:
    """메타 키(_note, targets 등)를 제거하고 각 툴 스키마에 맞게 변환."""
    out = {}
    if "url" in entry:
        if for_tool == "claude":
            out["type"] = "http"
        out["url"] = entry["url"]
        if "headers" in entry:
            out["headers"] = entry["headers"]
    else:
        if "command" in entry:
            out["command"] = entry["command"]
        if "args" in entry:
            out["args"] = entry["args"]
        if "env" in entry:
            out["env"] = entry["env"]
        if "cwd" in entry:
            out["cwd"] = entry["cwd"]
    return out


def toml_str(val: str) -> str:
    return json.dumps(val, ensure_ascii=False)


def render_codex_mcp_toml(servers: dict) -> str:
    lines = [MANAGED_START]
    for name, cfg in servers.items():
        key = name if re.match(r"^[A-Za-z0-9_-]+$", name) else toml_str(name)
        lines.append(f"[mcp_servers.{key}]")
        if "url" in cfg:
            lines.append(f"url = {toml_str(cfg['url'])}")
        else:
            lines.append(f"command = {toml_str(cfg['command'])}")
            if "args" in cfg:
                arr = ", ".join(toml_str(a) for a in cfg["args"])
                lines.append(f"args = [{arr}]")
            if "cwd" in cfg:
                lines.append(f"cwd = {toml_str(cfg['cwd'])}")
            if "env" in cfg and cfg["env"]:
                lines.append("")
                lines.append(f"[mcp_servers.{key}.env]")
                for ek, ev in cfg["env"].items():
                    lines.append(f"{ek} = {toml_str(str(ev))}")
        lines.append("")
    lines.append(MANAGED_END)
    return "\n".join(lines) + "\n"


def sync_mcp():
    if not MASTER_MCP_PATH.exists():
        print(f"[SKIP] 마스터 MCP 파일 없음: {MASTER_MCP_PATH}")
        return

    master = json.loads(MASTER_MCP_PATH.read_text(encoding="utf-8"))
    raw_servers = master.get("mcpServers", {})

    agy_servers = {}
    claude_servers = {}
    codex_servers = {}

    for name, cfg in raw_servers.items():
        targets = cfg.get("targets", ["antigravity", "claude", "codex"])
        if "antigravity" in targets:
            agy_servers[name] = clean_server_entry(cfg, "antigravity")
        if "claude" in targets:
            claude_servers[name] = clean_server_entry(cfg, "claude")
        if "codex" in targets:
            codex_servers[name] = clean_server_entry(cfg, "codex")

    # 1. Antigravity (~/.gemini/config/mcp_config.json)
    AGY_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    AGY_MCP_PATH.write_text(
        json.dumps({"mcpServers": agy_servers}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"[Antigravity] MCP {len(agy_servers)}개 반영 -> {AGY_MCP_PATH}")
    print("  -", ", ".join(agy_servers.keys()) or "(없음)")

    # 2. Claude (~/.claude.json) - 기존 mcpServers에 병합만 수행 (타 설정 보존)
    if CLAUDE_JSON_PATH.exists() and claude_servers:
        shutil.copy2(CLAUDE_JSON_PATH, str(CLAUDE_JSON_PATH) + ".bak")
        cdata = json.loads(CLAUDE_JSON_PATH.read_text(encoding="utf-8"))
        existing = cdata.setdefault("mcpServers", {})
        for name, cfg in claude_servers.items():
            existing[name] = cfg
        CLAUDE_JSON_PATH.write_text(
            json.dumps(cdata, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"[Claude]      MCP {len(claude_servers)}개 병합 -> {CLAUDE_JSON_PATH}")
    else:
        print("[Claude]      추가 병합 대상 없음 (기존 플러그인/프로젝트 설정 유지)")

    # 3. Codex (~/.codex/config.toml) - managed 블록만 교체
    if CODEX_CONFIG_PATH.exists():
        shutil.copy2(CODEX_CONFIG_PATH, str(CODEX_CONFIG_PATH) + ".sync-bak")
        content = CODEX_CONFIG_PATH.read_text(encoding="utf-8")
        block = render_codex_mcp_toml(codex_servers) if codex_servers else ""
        pattern = re.compile(
            re.escape(MANAGED_START) + r".*?" + re.escape(MANAGED_END) + r"\n?",
            re.DOTALL,
        )
        if pattern.search(content):
            new_content = pattern.sub(block, content)
        else:
            sep = "\n" if content.endswith("\n") else "\n\n"
            new_content = content + (sep + block if block else "")
        CODEX_CONFIG_PATH.write_text(new_content, encoding="utf-8")
        print(f"[Codex]       MCP {len(codex_servers)}개 반영 -> {CODEX_CONFIG_PATH}")
        print("  -", ", ".join(codex_servers.keys()) or "(없음)")


def collect_plugin_skills(enabled_map: dict, installed: dict, workspace: Path | None = None) -> dict[str, Path]:
    """플러그인별 스킬 디렉터리({skill_name: Path}) 수집."""
    skills: dict[str, Path] = {}
    seen_plugin_names = set()

    # 동일 플러그인 중복 방지: claude-plugins-official 우선
    ordered_keys = sorted(
        enabled_map.keys(),
        key=lambda k: (0 if k.endswith("@claude-plugins-official") else 1, k),
    )

    for plug_key in ordered_keys:
        if not enabled_map.get(plug_key, False):
            continue
        if plug_key not in installed:
            continue

        short_name = plug_key.split("@")[0]
        if short_name in seen_plugin_names:
            continue

        plug_entries = installed[plug_key]
        chosen = plug_entries[0]
        if workspace is not None:
            for e in plug_entries:
                if e.get("projectPath") == str(workspace):
                    chosen = e
                    break

        skills_dir = Path(chosen["installPath"]) / "skills"
        if skills_dir.is_dir():
            found = list(skills_dir.glob("*/SKILL.md"))
            if found:
                seen_plugin_names.add(short_name)
                for skill_md in sorted(found):
                    skill_dir = skill_md.parent
                    skills.setdefault(skill_dir.name, skill_dir)

    return skills


def sync_skill_symlinks(target_dir: Path, desired: dict[str, Path]) -> int:
    """target_dir 안에 <skill_name> 심볼릭 링크를 깔끔하게 동기화."""
    target_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = target_dir / ".sync-ai-managed.json"
    prev_managed = set()
    if manifest_path.exists():
        try:
            prev_managed = set(json.loads(manifest_path.read_text(encoding="utf-8")))
        except Exception:
            prev_managed = set()

    for old_name in prev_managed - set(desired.keys()):
        p = target_dir / old_name
        if p.is_symlink():
            p.unlink()

    managed = []
    for name, src in sorted(desired.items()):
        dst = target_dir / name
        if dst.exists() or dst.is_symlink():
            if dst.is_symlink():
                if name not in prev_managed and dst.resolve() == src.resolve():
                    continue
                if dst.resolve() != src.resolve():
                    dst.unlink()
                    dst.symlink_to(src)
                managed.append(name)
            else:
                continue
        else:
            dst.symlink_to(src)
            managed.append(name)

    manifest_path.write_text(json.dumps(sorted(managed), indent=2) + "\n", encoding="utf-8")
    return len(managed)


def sync_skills(workspaces: list[Path]):
    if not CLAUDE_SETTINGS_PATH.exists() or not CLAUDE_INSTALLED_PLUGINS_PATH.exists():
        print("[SKIP] Claude 설정 또는 플러그인 목록 없음")
        return

    user_settings = json.loads(CLAUDE_SETTINGS_PATH.read_text(encoding="utf-8"))
    user_enabled = user_settings.get("enabledPlugins", {})
    installed = json.loads(CLAUDE_INSTALLED_PLUGINS_PATH.read_text(encoding="utf-8")).get("plugins", {})

    # 긴 슬래시 커맨드(/config:..:..:..) 원인이 되는 skills.json 제거
    if AGY_SKILLS_PATH.exists():
        AGY_SKILLS_PATH.unlink()

    # 1. ~/.agents/skills -> ~/.claude/skills 동기화
    if AGENTS_SKILLS_DIR.is_dir() and CLAUDE_SKILLS_DIR.is_dir():
        claude_extra: dict[str, Path] = {}
        for skill_md in sorted(AGENTS_SKILLS_DIR.glob("*/SKILL.md")):
            sdir = skill_md.parent
            if sdir.name in ("computer-use",):
                continue
            # 이미 링크가 있는 스킬도 넣는다. 빼면 sync_skill_symlinks 가 지난 관리 목록에만 있는
            # 스킬로 보고 링크를 지워서, 실행할 때마다 기존 링크가 지워졌다 생겼다 한다.
            claude_extra[sdir.name] = sdir.resolve()
        if claude_extra:
            c_count = sync_skill_symlinks(CLAUDE_SKILLS_DIR, claude_extra)
            print(f"[Claude]      공용 스킬 심볼릭 링크 {c_count}개 동기화 -> {CLAUDE_SKILLS_DIR}")
        else:
            print("[Claude]      전역 스킬 최신 상태 (추가 대상 없음)")

    # 2. Global Antigravity skills (~/.gemini/config/skills/<name>)
    global_skills: dict[str, Path] = {}
    for base_dir in [CLAUDE_SKILLS_DIR, AGENTS_SKILLS_DIR]:
        if base_dir.is_dir():
            for skill_md in sorted(base_dir.glob("*/SKILL.md")):
                skill_dir = skill_md.parent
                if skill_dir.name in ("stack-diagram", "synced", "computer-use"):
                    continue
                global_skills.setdefault(skill_dir.name, skill_dir.resolve())

    for name, path in collect_plugin_skills(user_enabled, installed).items():
        global_skills.setdefault(name, path)

    agy_skills_dir = AGY_CONFIG_DIR / "skills"
    g_count = sync_skill_symlinks(agy_skills_dir, global_skills)
    print(f"[Antigravity] 전역 스킬 심볼릭 링크 {g_count}개 동기화 -> {agy_skills_dir}")

    # 3. Global Codex skills (~/.codex/skills/<name>)
    if CODEX_CONFIG_PATH.exists():
        import tomllib
        cdata = tomllib.loads(CODEX_CONFIG_PATH.read_text(encoding="utf-8"))
        codex_enabled_short = {
            pk.split("@")[0]
            for pk, pv in cdata.get("plugins", {}).items()
            if isinstance(pv, dict) and pv.get("enabled")
        }
        codex_plugin_enabled = {
            k: v for k, v in user_enabled.items()
            if v and k.split("@")[0] not in codex_enabled_short
        }
        codex_skills: dict[str, Path] = {}
        for base_dir in [CLAUDE_SKILLS_DIR, AGENTS_SKILLS_DIR]:
            if base_dir.is_dir():
                for skill_md in sorted(base_dir.glob("*/SKILL.md")):
                    skill_dir = skill_md.parent
                    if skill_dir.name in ("stack-diagram", "synced", "computer-use"):
                        continue
                    codex_skills.setdefault(skill_dir.name, skill_dir.resolve())
        for name, path in collect_plugin_skills(codex_plugin_enabled, installed).items():
            codex_skills.setdefault(name, path)

        x_count = sync_skill_symlinks(CODEX_SKILLS_DIR, codex_skills)
        print(f"[Codex]       전역 스킬 심볼릭 링크 {x_count}개 동기화 -> {CODEX_SKILLS_DIR}")

    # 4. Workspace skills (<workspace>/.agents/skills/<name> — Antigravity & Codex 공용)
    for ws in workspaces:
        ws_claude_settings = ws / ".claude" / "settings.json"
        if not ws_claude_settings.exists():
            continue
        ws_skills_json = ws / ".agents" / "skills.json"
        if ws_skills_json.exists():
            ws_skills_json.unlink()

        ws_settings = json.loads(ws_claude_settings.read_text(encoding="utf-8"))
        ws_enabled = {
            k: v for k, v in ws_settings.get("enabledPlugins", {}).items()
            if v and not user_enabled.get(k, False)
        }
        ws_skills = collect_plugin_skills(ws_enabled, installed, workspace=ws)
        if ws_skills:
            ws_skills_dir = ws / ".agents" / "skills"
            w_count = sync_skill_symlinks(ws_skills_dir, ws_skills)
            print(f"[Workspace]   스킬 심볼릭 링크 {w_count}개 동기화 -> {ws_skills_dir}")


def main():
    parser = argparse.ArgumentParser(description="Sync shared MCP & skills across Antigravity, Claude, and Codex.")
    parser.add_argument("--workspace", action="append", help="추가로 동기화할 워크스페이스 경로 (여러 번 지정 가능)")
    args = parser.parse_args()

    sync_mcp()
    print()
    sync_skills(load_workspaces(args.workspace))


if __name__ == "__main__":
    main()
