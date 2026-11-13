# 可信门禁 GitHub 版：待办（未落地）

状态：只有说明，还没落地。本机版见 `tools/trusted/verify_from_main.ps1`（2026-11-13）。
本轮没有 push，没有装 gh，也没有建 `.github/workflows`，没有设分支保护。下面每一步都要用户单独决定。

## 前提
1. 用户决定 push 本地 master。本地 master 比 origin/master 领先若干提交，其中包括门禁提交。
2. master 要先能单独通过门禁。现在 master 上的业务代码落后于工作区：基线和测试都是按工作区建的，所以在纯 master 上跑 `verify -Fast` 会判红（L1 有 5 条，scan 有 new=43 条，lua 测试失败）。业务改动进 master 以后，CI 才会是绿的。
3. C# 测试和 Harness（`Assets/Editor/Tests/**`、`Assets/Editor/AgentHarness/**`、`LuaFieldReader.cs`）还没进 master：它们依赖的 HomeSceneBootstrapper、Game.Security、Game.LocalBackend、PlatformUIEventChecks 等都没提交。要等业务代码一起进。

## 工作流草案（`.github/workflows/trusted-gate.yml`，待写）
- 触发：用 `pull_request`，目标分支是 master。
- 两份 checkout：
  - 被检查对象：`actions/checkout`，`ref: ${{ github.event.pull_request.head.sha }}`，放到 `target/`。
  - 可信副本：`actions/checkout`，`ref: ${{ github.event.pull_request.base.sha }}`，放到 `trusted/`。
- 用 `trusted/tools/verify.ps1 -Fast -ProjectRoot target -OutDir out/static` 跑静态门禁，换成 runner 上可用的 shell 和路径。
- GATE-TAMPER：用 `git diff --name-status base...head` 匹配 `trusted/tools/trusted/protected_paths.txt`，逻辑和本机版一致。碰到受保护路径就失败，并要求人工审核。
- 要不要用 `pull_request_target`：它用 base 分支上的 workflow 定义，有 secrets 和写权限，所以绝对不能执行 PR 里的代码。这里只读 PR 文件做静态扫描，也必须锁死 `permissions: contents: read`，并且不传 secrets。默认先用 `pull_request` 加上面的“base 检出到 trusted/”。PR 改 workflow 文件本身的风险由 CODEOWNERS 和分支保护兜底。
- 待核：GitHub 托管 Windows runner 上有没有 luacheck 和 lua，或者改用 ubuntu runner；那样 verify.ps1 需要 pwsh 兼容（本机只有 PowerShell 5.1）。
- `../tests/*.lua` 在 `My project` 仓库外面（属于上级目录的另一个仓库），CI 拿不到。要么先迁进 `My project/tests/`，要么在 CI 里把它们标成 SKIP 并说明原因。

## CODEOWNERS（`.github/CODEOWNERS`，待写）
```
/tools/            @fyt2001
/.luacheckrc       @fyt2001
/AGENTS.md         @fyt2001
/tests/            @fyt2001
/Assets/Editor/Tests/        @fyt2001
/Assets/Editor/AgentHarness/ @fyt2001
/.codebuddy/rules/ @fyt2001
/.github/          @fyt2001
```

## 分支保护（master，待设）
- PR 必须通过 required status check `trusted-gate`。
- 必须有 Code Owner 审核（Require review from Code Owners）。
- 禁止 force push，禁止删除分支；管理员是否也受约束由用户决定。
- 待核：仓库 `fyt2001/Unity-Game-Project` 如果是私有仓库，免费计划下分支保护和 CODEOWNERS 强制审核可能用不了，要看当前 GitHub 计划。

## Unity 测试
- EditMode 和 PlayMode（Harness）留在本机跑：`verify_from_main.ps1 -Unity`，或者 `tools/verify.ps1 -Full`。CI 上跑 Unity 要 license 和 Library 缓存，成本高，这轮不做。

## 第 4 步（不在本轮）
- 统计回滚，再考虑自动批准。
