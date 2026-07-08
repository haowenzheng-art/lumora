# 待 push 清单

> **生成时间**：2026-07-08
> **状态**：⚠️ 本地 commit 完成，**未推送 GitHub**（这台机器连不上 github.com）
>
> 如果你下次启动 Lumora 工作时看到这个文件，说明上次会话有未推送的改动。
> 网络通了之后手动 push，或在新机器上先 `git fetch` 再 cherry-pick / rebase。

---

## 待 push 的 commit（按提交顺序）

| # | hash | 类型 | 标题 |
|---|---|---|---|
| 1 | `e7b8686` | docs | README 同步 v2.2.0 |
| 2 | `19c2cfa` | feat | v2.3 启动补丁 SpiritView 强制眨眼 |
| 3 | `e440f2b` | feat | v2.3-B 用户偏好开关（破冰/自动进 ChatPage/打字机/骨架屏） |
| 4 | `ea60eef` | docs | CHANGELOG Unreleased 区更新（v2.3-B + 阶段判定计划） |

> 加上 v2.2 期间本地有但未 push 的：
> - `45dcfa0` docs: v2.2.0 发布说明
> - `v2.2.0` tag（本地，origin 没有）
> - 还有其他 v2.2 子项（v2.2-C / D / E / H 的 release commit）也都未推

---

## push 命令

```bash
# 主分支 + 全部 tag
git push origin main --follow-tags

# 或分两步：先 main，再 tag
git push origin main
git push origin v2.2.0

# 如果有冲突（origin 已经被别人推过），先 fetch 一下
git fetch origin
git log --oneline origin/main..HEAD  # 看本地领先多少
```

---

## 验证 push 成功

push 完后看 GitHub：
- https://github.com/haowenzheng-art/lumora/commits/main 应该显示最新的 commit
- https://github.com/haowenzheng-art/lumora/releases 应该看到 v2.2.0 + v2.3-B 标签

如果 push 后这个文件还在，说明又积攒了——删掉它，下次重新建。

---

## 上下文（为什么有这份清单）

这台机器（你正在跑 Lumora 开发的那台）现在**无法访问 github.com**——
- `git push` 报 `Connection was reset`
- 重试报 `Failed to connect to github.com port 443 after 21110ms`

之前 v2.2 期间就有同样问题（v2.2-summary 里写"v2.2 tag 暂未 push"）。
解决方案需要你在能联网的环境下手动推，或者给我 SSH 配置 / 备用 remote。

---

**下次启动如果看到这份文件还在 → 立刻 push → 删掉它**。这是纪律。