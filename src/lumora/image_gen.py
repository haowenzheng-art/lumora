"""Agnes Image 2.1 Flash 图像生成封装。

文档：https://apihub.agnes-ai.com/v1/images/generations
- 文生图：model + prompt + size 必填
- response_format 必须放 extra_body，不能放顶层
- return_base64=true 时返回 b64_json
"""
from __future__ import annotations

import base64
import json
import os
import urllib.request
import urllib.error
from pathlib import Path


AGNES_URL = "https://apihub.agnes-ai.com/v1/images/generations"
AGNES_MODEL = "agnes-image-2.1-flash"


def load_agnes_key() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    for _ in range(5):
        candidate = os.path.join(here, "agnes.txt")
        if os.path.exists(candidate):
            with open(candidate, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("API"):
                        sep = "：" if "：" in line else ":"
                        key = line.split(sep, 1)[1].strip()
                        if key:
                            return key
        here = os.path.dirname(here)
    raise FileNotFoundError("agnes.txt not found or API key missing")


def generate_image(
    prompt: str,
    size: str = "1024x1024",
    timeout: int = 180,
) -> bytes:
    """文生图，返回 PNG 字节。"""
    api_key = load_agnes_key()
    payload = {
        "model": AGNES_MODEL,
        "prompt": prompt,
        "size": size,
        "return_base64": True,
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        AGNES_URL,
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

    items = data.get("data") or []
    if not items:
        raise RuntimeError(f"空 data: {data}")
    item = items[0]
    b64 = item.get("b64_json")
    if not b64:
        # 退回 url
        url = item.get("url")
        if url:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                return r.read()
        raise RuntimeError(f"无 b64_json 也无 url: {item}")
    return base64.b64decode(b64)


# 立绘 prompt 模板：日漫风格人形精灵女孩，2.5D 体积感
SPRITE_PROMPT_TEMPLATE = (
    "日漫风格人形精灵女孩半身立绘，{variant}，"
    "柔和光影，深蓝紫色调，琥珀色点缀，"
    "2.5D 体积感，有阴影和层次，高细节，"
    "干净背景，居中构图，竖版"
)


def generate_sprite(variant: str, out_path: Path) -> Path:
    """生成一张精灵立绘。variant 描述气质。"""
    prompt = SPRITE_PROMPT_TEMPLATE.format(variant=variant)
    print(f"[生成中] variant={variant}")
    print(f"  prompt: {prompt}")
    png_bytes = generate_image(prompt, size="1024x1024")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(png_bytes)
    print(f"  saved: {out_path} ({len(png_bytes)} bytes)")
    return out_path


def generate_image_to_image(
    prompt: str,
    input_image_path: Path,
    size: str = "1024x1024",
    timeout: int = 240,
) -> bytes:
    """图生图。输入本地图片路径，返回 PNG 字节。

    Agnes 图生图要求：
    - image 数组放 extra_body 里（不是顶层）
    - 支持 Data URI Base64 输入
    - response_format 放 extra_body
    - 不需要 tags
    """
    api_key = load_agnes_key()
    with open(input_image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    data_uri = f"data:image/png;base64,{b64}"

    payload = {
        "model": AGNES_MODEL,
        "prompt": prompt,
        "size": size,
        "extra_body": {
            "image": [data_uri],
            "response_format": "b64_json",
        },
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        AGNES_URL,
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

    items = data.get("data") or []
    if not items:
        raise RuntimeError(f"空 data: {data}")
    item = items[0]
    b64_out = item.get("b64_json")
    if not b64_out:
        url = item.get("url")
        if url:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                return r.read()
        raise RuntimeError(f"无 b64_json 也无 url: {item}")
    return base64.b64decode(b64_out)


def generate_sprite_from_photo(
    input_photo: Path,
    out_path: Path,
    style_hint: str = "",
) -> Path:
    """从用户照片生成日漫风精灵立绘。"""
    prompt = (
        f"将这张照片转换为日漫风格人形精灵女孩立绘，{style_hint}，"
        "保留原图人物特征（发型、脸型、神态），"
        "柔和光影，深蓝紫色调，琥珀色点缀，"
        "2.5D 体积感，有阴影和层次，高细节，干净背景，居中构图，竖版"
    )
    print(f"[图生图] input={input_photo}")
    print(f"  prompt: {prompt}")
    png_bytes = generate_image_to_image(prompt, input_photo, size="1024x1024")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(png_bytes)
    print(f"  saved: {out_path} ({len(png_bytes)} bytes)")
    return out_path


if __name__ == "__main__":
    # 手动测试入口：生成两张预置立绘
    project_root = Path(__file__).resolve().parents[2]
    sprites_dir = project_root / "agent_data" / "xiaoyu" / "sprites"
    sprites_dir.mkdir(parents=True, exist_ok=True)
    generate_sprite(
        "温柔安静气质，长发，浅笑，眼神柔和，穿浅色长裙",
        sprites_dir / "spirit_gentle.png",
    )
    generate_sprite(
        "灵动俏皮气质，短发或双马尾，俏皮表情，眼神有光，穿轻便服装",
        sprites_dir / "spirit_lively.png",
    )
    print("\n=== 立绘生成完毕 ===")

