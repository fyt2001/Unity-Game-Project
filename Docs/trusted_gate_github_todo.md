# 可信门禁 GitHub 版：现状

状态（2026-11-13，上海时间）：工作流和 CODEOWNERS 已在 `master`（`2411262`）。仓库已公开。`master` 已有分支保护：必须走 PR、需要 1 个批准、必须有 Code Owner 审核、禁止 force push 和删除；保留管理员绕过（仓库只有一人，关掉会导致自己的 PR 没人能批）。

`trusted-gate` 还不是 required check：该工作流从未在 PR 上跑过，GitHub 的状态检查选择器里还没有这项。本 PR 用来跑一次检查；通过后再把它补进保护规则。

本机 runner 仍见 `tools/trusted/verify_from_main.ps1`。

## 已落地

- 工作流：`.github/workflows/trusted-gate.yml`（`pull_request` 到 `master`；`permissions: contents: read`；`windows-latest`；从 base 取出 `verify_from_main.ps1` 再对 head 检查）。
- CODEOWNERS：`/tools/`、`/.luacheckrc`、`/AGENTS.md`、`/tests/`、`/Assets/Editor/Tests/`、`/Assets/Editor/AgentHarness/`、`/.codebuddy/rules/`、`/.github/` 归 `@fyt2001`。
- Lua 回归测试已迁进仓库 `tests/`，`tools/lua_tests.json` 已指向这些路径。
- 分支保护规则：https://github.com/fyt2001/Unity-Game-Project/settings/branch_protection_rules/86284936

## 本 PR 之后还要做

- 等本 PR 的 `trusted-gate` 跑完，把同名检查设为 required。
- 在此之前，合并不会被这项检查拦住。

## Unity 测试（仍在本机）

- EditMode / PlayMode 不进 CI（需要 license）。完整核验曾到 `5eebac4`：EditMode 20 用例 19 通过、1 隔离跳过 `Lua_gm_s01`，PlayMode 通过。

## 不要入库

- 本地已填的 `Assets/Game/Scripts/Security/LuaProtectionKeys.cs`（仓库里只保留空值）。
- 大字体等未跟踪资源。

## 第 4 步（仍不做）

- 统计回滚后再考虑自动批准。