--[[
=============================================================================
Define.lua - C# 类型全局别名定义
=============================================================================
来源: ShaoNvClient_H02 Common/Define.lua 提取精华
说明: 为频繁使用的 Unity C# 类型创建 Lua 全局别名，减少 CS. 前缀开销
=============================================================================
]]

-- Unity Engine 核心类型
GameObject             = CS.UnityEngine.GameObject
Transform              = CS.UnityEngine.Transform
RectTransform          = CS.UnityEngine.RectTransform
Vector2                = CS.UnityEngine.Vector2
Vector3                = CS.UnityEngine.Vector3
Color                  = CS.UnityEngine.Color
Resources              = CS.UnityEngine.Resources
Mathf                  = CS.UnityEngine.Mathf
Time                   = CS.UnityEngine.Time
Screen                 = CS.UnityEngine.Screen
Input                  = CS.UnityEngine.Input
Application            = CS.UnityEngine.Application
Object                 = CS.UnityEngine.Object
Font                   = CS.UnityEngine.Font

-- Unity UI 类型
Unity_Canvas           = CS.UnityEngine.Canvas
Unity_CanvasScaler     = CS.UnityEngine.UI.CanvasScaler
Unity_GraphicRaycaster = CS.UnityEngine.UI.GraphicRaycaster
Unity_Image            = CS.UnityEngine.UI.Image
Unity_RawImage         = CS.UnityEngine.UI.RawImage
Unity_Text             = CS.UnityEngine.UI.Text
Unity_Button           = CS.UnityEngine.UI.Button
Unity_Slider           = CS.UnityEngine.UI.Slider
Unity_ScrollRect       = CS.UnityEngine.UI.ScrollRect
Unity_Toggle           = CS.UnityEngine.UI.Toggle
Unity_InputField       = CS.UnityEngine.UI.InputField
Unity_Dropdown         = CS.UnityEngine.UI.Dropdown
Unity_CanvasGroup      = CS.UnityEngine.CanvasGroup
Unity_Animator         = CS.UnityEngine.Animator

-- Unity 场景管理
SceneManager           = CS.UnityEngine.SceneManagement.SceneManager
LoadSceneMode          = CS.UnityEngine.SceneManagement.LoadSceneMode

-- Unity 其他
Unity_Debug            = CS.UnityEngine.Debug
Unity_PlayerPrefs      = CS.UnityEngine.PlayerPrefs
Unity_RenderMode       = CS.UnityEngine.RenderMode
