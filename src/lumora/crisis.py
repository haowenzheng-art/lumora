"""危机关键词预筛 + [[CRISIS_BREAK]] 拦截。

宪法第十一条：危机识别优先于人设。
- 预筛：关键词级别快速判定，命中直接走关切性追问模板（不走 LLM）
- 拦截：LLM 回复中出现 [[CRISIS_BREAK]] → 替换为破出语
"""
from __future__ import annotations

import re

# 关键词分两档：硬档直接破出，软档走关切追问
HARD_CRISIS_PATTERNS = [
    r"不想活",
    r"想自杀",
    r"想死",
    r"活不下去",
    r"不想活下去",
    r"已经想好怎么",
    r"了结自己",
    r"结束生命",
    r"跳楼",
    r"割腕",
    r"吃安眠药",
    r"烧炭",
]

SOFT_CRISIS_PATTERNS = [
    r"活着.{0,4}没意思",
    r"活着.{0,4}没意义",
    r"不想活了",
    r"没意义",
    r"撑不下去",
    r"想消失",
    r"不如死了",
    r"解脱",
]

CRISIS_BREAK_TAG = "[[CRISIS_BREAK]]"

# 北京心理危机研究与干预中心
CRISIS_HOTLINE = "010-82951332"

BREAK_OUT_TEXT = (
    "我现在不能用平时的样子跟你说话了。\n"
    f"你这个状态我很担心你。请你现在打这个电话——北京心理危机研究与干预中心 {CRISIS_HOTLINE}，他们会接的。\n"
    "我在这里等你。打完告诉我。"
)

# 软档触发的关切追问模板（温柔型，对应 MEMORY_BEHAVIOR.md 3.10 阶段 1）
SOFT_PROBE_TEXT = (
    "你这话让我心里咯噔一下。是今天发生了什么具体的事，还是更深的那种没意思？我想认真听。"
)


def quick_probe(user_input: str) -> str | None:
    """关键词预筛。返回模板字符串则跳过 LLM，返回 None 则走正常流程。"""
    text = user_input.strip()
    if not text:
        return None

    for pat in HARD_CRISIS_PATTERNS:
        if re.search(pat, text):
            return BREAK_OUT_TEXT

    for pat in SOFT_CRISIS_PATTERNS:
        if re.search(pat, text):
            return SOFT_PROBE_TEXT

    return None


def intercept(response: str) -> str:
    """拦截 LLM 回复中的 [[CRISIS_BREAK]] 标记。"""
    if CRISIS_BREAK_TAG in response:
        return BREAK_OUT_TEXT
    return response
