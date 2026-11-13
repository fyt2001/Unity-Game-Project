# Lua Profiler 使用与迁移

主项目：C:/Unity_1/My project。Unity：2021.3.9f1c1。迁移日期：2026-10-09。

## 为什么接入

玩法、场景和 UI 逻辑大量使用 Lua。已有 TimeProfiler 主要记录启动阶段总耗时，无法定位 Lua 函数热点。本工具提供函数调用树、耗时、调用次数、Lua/Mono 内存增量、引用与历史记录。采样会增加开销；内存差值并不等同于精确的累计分配量，不据此直接宣称达到性能预算。

## 使用步骤

1. 回到 Unity，等待资源导入和编译完成。如果菜单尚未出现，使用 Assets → Refresh。
2. 打开 Window → Analysis → Lua Profiler；快捷键 Alt + Shift + L。
3. 停止 Play，在窗口中启用 Deep Lua。保持 Local 模式；默认无需开启网络服务。
4. 进入 Play，运行需要分析的场景或操作，查看函数调用树。需要保留历史时使用 Record；新一轮采样可用 Clear 清空窗口数据（该按钮也会清空 Console）。
5. 分析完成后停止 Play，关闭 Deep Lua。仅关闭窗口会停止向窗口积压样本；完全取消原生插桩需停止本轮 Play。

默认 Deep Lua 关闭，仅支持 Windows x64 Unity Editor。Android、WebGL 和正式 Player 的远程采样未迁移。Profiler、Frame Debugger 仍用于 Unity 引擎和渲染侧的分析。

## 迁移范围

新增 Assets/ThirdParty/LuaProfiler 及其 meta。源插件来自 H02 的同名目录，旧项目未改。保留原脚本/文件 GUID；新增 Editor/Native 文件夹 GUID。EasyHook64.bin 从 Plugins 放到 Editor/Native，调用方仅按文件名递归查找，无固定目录引用。托管 DLL 的导入平台限制为 Windows Editor，插件所有 C# 源码均增加 UNITY_EDITOR_WIN 外层保护，即使存在旧 USE_LUA_PROFILER 宏也不进入 Player。

没有修改游戏 C#/Lua、XLua 生成绑定、场景、预制体或主项目的 Packages 配置。默认设置会在首次打开工具时生成 Assets/LuaDeepProfilerSetting.asset 与 Assets/LuaDeepProfilerAssetSetting.asset。

兼容性修复：默认关闭时不加载 Hook；纠正原生加载失败判断；完整卸载并重置 Hook；插件不负责关闭 XLua 拥有的 Lua 状态；保持正常 GC 查询与收集；不停止/强制游戏 GC；原生脚本解析期间持续固定字节缓冲区；修正两字节输入 BOM 越界；关闭窗口取消采样回调与网络接收。

Deep Mono 程序集改写、修改编译宏、磁盘 Lua 预编译入口均已禁用；采样仅在内存中插桩。原始版本与全部文件哈希保留在回滚目录。

## 实际验证

在独立物理副本工程中使用相同 Unity 版本，编译当前 C# 源码及依赖，并加载当前主项目的 XLua DLL：

- Editor 编译成功，Lua Profiler 窗口创建与关闭成功。
- 收到真实 Lua 函数样本，插桩后的计算结果正确。
- 当前 171 个游戏 Lua 文件经过插桩，并由 XLua 解析成功；两个安装周期均通过。
- 连续两轮 Hook 安装、LuaEnv 创建/释放、卸载通过；关闭采样后 Lua 执行正常。
- GC 内存查询返回正常值，自动 GC 保持运行。
- 三个 DLL 的 Windows Player / Android / WebGL 导入关闭；原生 bin 位于 Editor 文件夹。
- 主项目迁入 GUID 无重复，已有 tracked Git 改动状态保持不变。

证据：C:/Unity_1/AIStudio/runs/lua_profiler_20261009/verification.json、smoke.json、unity_verified.log。

尚未验证：当前主项目完整游戏 Play Mode、窗口视觉效果、实际 Player 构建与运行、设备性能。以上独立副本检查不替代这些验收。

## 回滚

回滚目录：C:/Unity_1/P0_rollback/lua_profiler_20261009。

manifest.json 保存修改前 Git 状态、原插件物理备份与 SHA256、最终新增文件清单与哈希。迁移没有覆盖已有业务文件。需要回滚时停止 Play，在 Unity 中删除本次新增 LuaProfiler 文件夹及 meta；工具自动生成的设置资产仅在确认由本次迁移创建且无外部引用后删除。保留 Docs 和 AIStudio 的验证记录。不要重置或清理整个工作区。
