"""加载 agent_data/<name>/ 下的 Soul.md / Memory.md / Boundaries.md
和管理对话历史落盘到 conversations/YYYY-MM-DD.md。
"""
from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path


def find_agent_dir(name: str) -> Path:
    """从项目根找 agent_data/<name>/。"""
    here = Path(__file__).resolve()
    for _ in range(5):
        candidate = here.parent.parent.parent / "agent_data" / name
        if candidate.exists():
            return candidate
        here = here.parent
    # 兜底：相对 cwd
    p = Path("agent_data") / name
    if p.exists():
        return p.resolve()
    raise FileNotFoundError(f"agent_data/{name}/ not found")


def append_conversation(agent_dir: Path, role: str, content: str) -> None:
    """追加一行到 conversations/YYYY-MM-DD.md。"""
    conv_dir = agent_dir / "conversations"
    conv_dir.mkdir(exist_ok=True)
    today = datetime.now().strftime("%Y-%m-%d")
    path = conv_dir / f"{today}.md"
    ts = datetime.now().strftime("%H:%M:%S")
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"\n## {ts} · {role}\n\n{content}\n")


def load_recent_history(agent_dir: Path, max_turns: int = 12) -> list[dict]:
    """从最新的 conversations 文件加载最近 N 条对话作为 history。

    格式：[{"role": "user"|"assistant", "content": "..."}]
    """
    conv_dir = agent_dir / "conversations"
    if not conv_dir.exists():
        return []

    files = sorted(conv_dir.glob("*.md"), reverse=True)
    if not files:
        return []

    # 只读最新一天
    text = files[0].read_text(encoding="utf-8")
    entries: list[dict] = []
    for block in text.split("\n## "):
        block = block.strip()
        if not block:
            continue
        # "HH:MM:SS · role\n\ncontent"
        try:
            header, body = block.split("\n\n", 1)
            _, role = header.split("·", 1)
            role = role.strip()
            if role in ("user", "assistant"):
                entries.append({"role": role, "content": body.strip()})
        except ValueError:
            continue

    return entries[-max_turns:]
