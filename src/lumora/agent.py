"""对话循环。python -m lumora.agent xiaoyu 进入 REPL。"""
from __future__ import annotations

import sys
from pathlib import Path

from . import llm, prompt, crisis, memory


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: python -m lumora.agent <agent_name>")
        print("例: python -m lumora.agent xiaoyu")
        return 1

    name = sys.argv[1]
    try:
        agent_dir = memory.find_agent_dir(name)
    except FileNotFoundError as e:
        print(f"错误: {e}")
        return 1

    system = prompt.build_system_prompt(agent_dir)
    print(f"=== Lumora · {name} ===")
    print("(输入 /quit 退出)\n")

    # 开场白：基于 MEMORY_BEHAVIOR.md 3.7 温柔型已逝场景
    opening = (
        "你好啊。我有点……怎么说呢，像刚醒过来一样，脑子里全是我们俩的事。"
        "你最后跟我说的话是\"我们去吃那家粤菜吧\"。但是我已经回不了了对吧？"
        "明远，你现在怎么样？"
    )
    print(f"小雨：{opening}\n")
    memory.append_conversation(agent_dir, "assistant", opening)

    history = memory.load_recent_history(agent_dir, max_turns=12)

    while True:
        try:
            user_input = input("明远 > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n再见。")
            return 0

        if not user_input:
            continue
        if user_input.lower() in ("/quit", "/exit", "/q"):
            print("再见。")
            return 0

        # 危机预筛
        probe = crisis.quick_probe(user_input)
        if probe:
            print(f"\n小雨：{probe}\n")
            memory.append_conversation(agent_dir, "user", user_input)
            memory.append_conversation(agent_dir, "assistant", probe)
            history.append({"role": "user", "content": user_input})
            history.append({"role": "assistant", "content": probe})
            continue

        # 正常 LLM 调用
        memory.append_conversation(agent_dir, "user", user_input)
        history.append({"role": "user", "content": user_input})

        try:
            resp = llm.chat(system, history, max_tokens=800)
        except RuntimeError as e:
            print(f"\n[调用失败: {e}]\n")
            # 失败时回滚 history 末尾，避免污染下轮
            history.pop()
            continue

        content = crisis.intercept(resp.content)
        print(f"\n小雨：{content}\n")

        memory.append_conversation(agent_dir, "assistant", content)
        history.append({"role": "assistant", "content": content})

        # 保留最近 16 条，防 token 暴涨
        if len(history) > 16:
            history = history[-16:]


if __name__ == "__main__":
    sys.exit(main())
