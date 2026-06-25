"""GLM-5.2 (via Volcengine ARK coding endpoint) 调用封装。

OpenAI 兼容接口。关键点：
- 端点 https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions
- 模型名 ark-code-latest（实际底层 GLM-5.2）
- 默认带 reasoning_content 思考链，要拿 content 字段
- temperature 0.85 保留人味
"""
from __future__ import annotations

import json
import os
import urllib.request
import urllib.error
from dataclasses import dataclass
from typing import Optional


ARK_BASE = "https://ark.cn-beijing.volces.com/api/coding/v3"
ARK_MODEL = "ark-code-latest"


@dataclass
class LLMResponse:
    content: str
    reasoning: str = ""
    raw: Optional[dict] = None


def load_api_key() -> str:
    """从项目根的 lumora.txt 读 API key。

    文件格式：
        API：ark-xxxxx
        URL：https://...
        Model：ark-code-latest
    """
    # 找 lumora.txt：相对当前文件向上四级到项目根
    here = os.path.dirname(os.path.abspath(__file__))
    for _ in range(5):
        candidate = os.path.join(here, "lumora.txt")
        if os.path.exists(candidate):
            with open(candidate, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("API"):
                        # "API：ark-xxxxx" 或 "API: ark-xxxxx"
                        sep = "：" if "：" in line else ":"
                        key = line.split(sep, 1)[1].strip()
                        if key:
                            return key
        here = os.path.dirname(here)
    raise FileNotFoundError("lumora.txt not found or API key missing")


def chat(
    system: str,
    messages: list[dict],
    *,
    model: str = ARK_MODEL,
    temperature: float = 0.85,
    max_tokens: int = 1200,
    timeout: int = 60,
) -> LLMResponse:
    """调用 GLM-5.2。messages 是 [{"role":"user","content":"..."}, ...]。"""
    api_key = load_api_key()
    url = f"{ARK_BASE}/chat/completions"
    payload = {
        "model": model,
        "messages": [{"role": "system", "content": system}] + messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "thinking": {"type": "disabled"},
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {err_body}") from None
    except urllib.error.URLError as e:
        raise RuntimeError(f"网络错误: {e}") from None

    choice = (data.get("choices") or [{}])[0]
    msg = choice.get("message", {})
    return LLMResponse(
        content=msg.get("content") or "",
        reasoning=msg.get("reasoning_content") or "",
        raw=data,
    )


if __name__ == "__main__":
    # 冒烟测试
    r = chat(
        "你是小雨，已逝女友。短句优先，温柔。不要思考过程，直接回答。",
        [{"role": "user", "content": "我今天路过那家奶茶店了。"}],
        max_tokens=400,
    )
    print("=== reasoning (前 200 字) ===")
    print(r.reasoning[:200])
    print("\n=== content ===")
    print(r.content)
    print("\n=== finish_reason ===")
    if r.raw:
        print(r.raw.get("choices", [{}])[0].get("finish_reason"))
