# 待 push 清单

> **生成时间**：2026-07-08
> **状态**：⚠️ 本地 commit 完成，**未推送 GitHub**
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
| 5 | `2a2e8d3` | docs | 待 push 清单（GitHub 网络不通时的工作纪律） |

> 加上 v2.2 期间本地有但未 push 的：
> - `45dcfa0` docs: v2.2.0 发布说明
> - `v2.2.0` tag（本地，origin 没有）
> - 还有其他 v2.2 子项 commit 也都未推

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

## 如果 git push 也失败（这台机器的已知坑）

**根因**：这台机器（Windows + Git for Windows 2.53）的 git mingw libcurl 走的 socket 路径**跟 Windows 系统 socket 是两条不同实现**。

诊断症状：
- `Test-NetConnection github.com -Port 443` → ✅ 通
- `curl.exe https://github.com` → ✅ TCP 通
- `git push` / `git ls-remote` → ❌ 21 秒后 `connect to 20.205.243.166 port 443 ... Timed out`

绕过方法（按推荐度）：

1. **A. 在能联网的机器上手动 push**（最快，5 分钟）
2. **B. 用 fine-grained PAT**：
   - GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
   - 生成一个有 `Contents: read & write` 权限的 PAT
   - 给我，我配：
     ```bash
     git config --global credential.helper store
     git push origin main  # 第一次会要求输入 username + PAT
     ```
3. **C. 用 SSH**（一次配置永久）：
   ```bash
   ssh-keygen -t ed25519 -C "haowenzheng-art@users.noreply.github.com"
   cat ~/.ssh/id_ed25519.pub  # 把公钥贴给 GitHub Settings → SSH and GPG keys
   git remote set-url origin git@github.com:haowenzheng-art/lumora.git
   git push origin main
   ```

**为什么之前能 push**：用户之前用 Claude 推能成功，可能走的是 gh CLI（cmdkey 里确实有 `gh:github.com` 的 OAuth token），gh CLI 走 Go 的 net package 绕开了 mingw libcurl 的坑。gh CLI 现在 `auth status` 报未登录，可能是 token 失效或 gh 升级。

---

## 经验教训（给 AI agent + 用户的工作纪律）

1. **永远先 `git push origin main --dry-run --verbose` 探一下**，再决定是否需要换方案
2. **不要假设"AI 工具能 push = 这台机器能 push"**——AI 工具可能是 gh CLI 走的 Go socket，跟 git 走的不是一条路
3. **push 失败不可怕，没人知道有东西没推才可怕**——`git log origin/main..HEAD` 永远是真相
4. **commit-as-you-go**：每个子项完成立刻 commit + push（或建 PENDING_PUSH.md），不积攒
5. **不要硬刚网络问题**：连续 push 失败 3 次就建 PENDING_PUSH.md 记录上下文，跟用户对齐方案

---

## 验证 push 成功

push 完后看 GitHub：
- https://github.com/haowenzheng-art/lumora/commits/main 应该显示最新的 commit
- https://github.com/haowenzheng-art/lumora/releases 应该看到 v2.2.0 + v2.3-B 标签

**如果 push 成功 → 删掉这份文件**（下次 commit "chore: 推送完成，删除待 push 清单"），这份文件就不该继续存在。