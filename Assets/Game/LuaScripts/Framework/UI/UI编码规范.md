# UI 框架 Lua 编码规范

> 适用范围：`Assets/Game/LuaScripts/Framework/UI` 及衍生 UI 代码。
> 本规范由代码清理过程（遗留/不规范问题复盘）沉淀而来，新增/修改代码必须遵守。
> 机器校验见仓库 `LuaScripts/.editorconfig`（编辑器与 CI 自动生效）。

---

## 1. 缩进（核心）

- **统一使用 Tab 缩进，禁止空格缩进**，同一文件内不得混用 Tab 与空格。
- 编辑器「Tab 宽度」显示设为 **4**（仅是显示宽度，文件内仍是 1 个 `\t` 字符）。
- 对齐用的连续空格也需避免；层级靠 Tab 表达。

## 2. 文件格式

- 编码：**UTF-8 无 BOM**。
- 换行：**LF（`\n`）**。
- 文件末尾保留一个换行符；去除行尾空白。

## 3. 模块文件头（Standard Format）

每个文件顶部 `--[[ ... ]]` 块包含以下字段（沿用现有约定）：

```
Module / Version / Author / Status / Target / Description / Dependencies / Usage
```

- `Status` 取值：
  - `Frozen (Public API)`：对外稳定接口，**禁止**随意改签名或删除（删除前需全仓确认无调用方）。
  - `Internal`：内部实现，可自由调整。

## 4. 命名

- 模块 / 类：PascalCase（`UIManager`、`UIWindow`）。
- 方法 / 局部变量：camelCase。
- 常量 / 枚举值：枚举表形式 `UIEnums.Xxx.Yyy`（`UIEnums.CachePolicy.NeverDestroy`）。
- 私有方法前缀 `_`（`UIManager:_reportOpenCost`）。

## 5. 注释

- 函数注释用 `---`（三横杠），参数/返回值用 `---@param` / `---@return`。

## 6. 错误处理与配置

- **配置缺失必须优雅失败**：先 `config.Has(name)` 判断，再 `config.Get(name)`；
  不要依赖 `Get` 内部的 `assert` 兜底（否则上层 `if not config then ...` 守卫会成为死代码）。
- 枚举常量必须存在且自洽，作为**单一事实来源**：
  - 例：`UIEnums.ZonePolicy` 必须定义 `Default`，且 `Default` 等同 `Normal`；
    业务写 `zonePolicy = UIEnums.ZonePolicy.Default` 才能正确解析，而不是落到 `nil` + 兜底分支。

## 7. 代码卫生

- **禁止遗留死代码**：全项目零调用的 helper 函数应删除（如已清理的
  `UIState.GetValidTransitions` / `IsTerminal` / `IsReusable` / `GetAllStates` / `GetStateCount`、
  `UIWindowStack.Bottom` / `Contains` / `IndexOf` / `RemoveWhere`、
  `UIWindowCache.Has` / `ClearByPolicy` / `Filter`）。
- 运算符 `and` / `or` 混合条件**必须加括号**明确优先级：`if (a and b) or c then`。
- 重复逻辑抽到私有方法（如 open-cost 计时 `UIManager:_reportOpenCost`）。
- 状态机变更必须走 `UIWindow:SetState`（含 `AssertTransition` 校验），禁止直接赋值 `self.state`。

## 8. 机器校验

仓库 `LuaScripts/.editorconfig` 已声明 `[*.lua] indent_style = tab` 等规则；
提交前请确保编辑器无缩进/编码告警。
