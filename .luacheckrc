--[[
.luacheckrc — My project (XLua) 静态检查门禁
=============================================================================
用途：luacheck 作为 Lua 静态检查门禁。XLua 运行期注入的全局、以及框架
      初始化时注入的 Unity 类型别名在此声明，避免误报。

接入：
    从工程根目录运行：
        pwsh tools/lint/run_gate.ps1
    或单独：
        luacheck Assets/Game/LuaScripts --no-cache --codes
    非 0 退出即阻断。

与规范的对齐：
    - std = "lua53"           对齐 XLua（Lua 5.3）；本机系统 lua 可能是 5.5，勿用系统解释器当准
    - max_line_length = 120   超长行记为 W631，暂不阻断（见 ignore）
    - 缩进以 Assets/Game/LuaScripts/.editorconfig 为准（tab）
]]

std = "lua53"
max_line_length = 120
self = false

-- 暂不阻断的码（后续可收紧；新的未定义全局 / 意外写全局仍会失败）：
-- 631 行过长  611 仅空白行  614 行尾空白
-- 212 未使用的 self（已由 self=false 覆盖，列在这里便于检索）
-- 211 未使用变量  213 未使用循环变量  311 赋值未使用
-- 431 遮蔽上值  542 空 if 分支
ignore = { "631", "611", "614", "212", "211", "213", "311", "431", "542" }

-- 允许的全局变量（运行期注入 + 项目框架注入）。
-- 不在表中的全局名会被 luacheck 报 undefined-global，借此捕获拼写错误 / 误用全局。
globals = {
    -- XLua 运行期
    "CS",            -- CS.UnityEngine.xxx 命名空间访问
    "typeof",        -- XLua 类型查询
    "IsNull",        -- 框架全局：判空（识别已 Destroy 的 userdata）
    "Logger",        -- 框架日志全局表（Logger.Log / LogError / ...）

    -- P0-2 起由 C# 注入的全局 tick 入口
    "__LuaTick",
    "__LuaLateTick",
    "__LuaFixedTick",
    -- P0-2 起由 C# 注入的离线开关（GameLaunch.cs）
    "Macro",

    -- 框架注入的 Unity 类型别名（UIComponentBinder / 框架初始化时挂到 _G）
    "Unity_Object", "Unity_GameObject", "Unity_Transform", "Unity_RectTransform",
    "Unity_Component", "Unity_Behaviour", "Unity_MonoBehaviour",
    "Unity_Canvas", "Unity_CanvasGroup", "Unity_Camera",
    "Unity_Color", "Unity_Vector2", "Unity_Vector3", "Unity_Vector4",
    "Unity_Quaternion", "Unity_Matrix4x4",
    "Unity_Button", "Unity_Toggle", "Unity_Slider", "Unity_ScrollRect",
    "Unity_Scrollbar", "Unity_InputField", "Unity_Text", "Unity_TMP_Text",
    "Unity_Image", "Unity_RawImage", "Unity_Sprite", "Unity_Texture",
    "Unity_Material", "Unity_Shader", "Unity_Mesh", "Unity_AudioSource",
    "Unity_Animator", "Unity_Animation", "Unity_ParticleSystem",
    "Unity_Mask", "Unity_RectMask2D", "Unity_LayoutGroup",
    "Unity_ContentSizeFitter", "Unity_GridLayoutGroup",
    "Unity_HorizontalLayoutGroup", "Unity_VerticalLayoutGroup",
    "Unity_Graphic", "Unity_MaskableGraphic", "Unity_EventSystems",

    -- Game/Common/Define.lua 注入的别名（原先漏配，UIHomeView 一直在吃同类误报）
    "Object",                        -- CS.UnityEngine.Object
    "Game_VirtualJoystick",          -- CS.VirtualJoystick
    "Game_HomeSceneBootstrapper",    -- CS.HomeSceneBootstrapper

    -- Framework.UI.Utils.BaseClass 有意暴露的全局
    "ClassType",
    "BaseClass",
}

-- xLua 5.3 仍常见的兼容别名（标准 lua53 里 unpack 已迁到 table.unpack）
read_globals = { "unpack" }

-- Define.lua / BaseClass.lua 是有意写全局的入口；其它文件再写全局会报 W111。
-- 这两个文件是有意写全局的入口；其它文件再写全局会报 W111。
-- W131（未使用的全局）是跨文件误报：Define 里定义、业务文件里用。
files["Assets/Game/LuaScripts/Common/Define.lua"] = {
    allow_defined_top = true,
    ignore = { "131" },
}
files["Assets/Game/LuaScripts/Framework/UI/Utils/BaseClass.lua"] = {
    allow_defined_top = true,
    ignore = { "131" },
}
