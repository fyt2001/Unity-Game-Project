// =============================================================================
// XLuaProjectConfig.cs - 项目级 XLua 生成配置（Editor-only，不进包）
// =============================================================================
// 用途：把「C# 事件 → Lua 回调」需要的委托类型显式登记进 CSharpCallLua 生成列表。
//
// 背景（为什么必须登记）：
//   XLua 的 ObjectTranslator.getCreatorUsingGeneric() 对「参数含值类型」的委托
//   会直接返回 null（见 ObjectTranslator.cs:375-381），不走泛型 Action<T> 兜底。
//   因此像 UnityEngine.Events.UnityAction<Vector2>（Vector2 是结构体）这类委托
//   若不写进 CSharpCallLua，运行期会抛：
//       InvalidCastException: This type must add to CSharpCallLua:
//       UnityEngine.Events.UnityAction`1[UnityEngine.Vector2]
//
// 触发场景：
//   Framework/UI/Component/UIListView.lua:56
//       self.scrollRect.onValueChanged:AddListener(self._onValueChanged)
//   ScrollRect.onValueChanged 的类型是 UnityEvent<Vector2>，
//   AddListener 需要 UnityAction<Vector2>，未登记 → GM 面板（唯一使用 UIListView 的
//   面板）在 UIGMView:OnCreate → AddComponent(UIListView) 时抛异常，整窗打不开。
//
// 其他同类隐患（当前无调用方，登记后一并消除）：
//   UISlider.lua:62     Slider.onValueChanged    -> UnityAction<float>
//   UIToggle.lua:57     Toggle.onValueChanged    -> UnityAction<bool>
//   UIInputField.lua:42 InputField.onValueChanged-> UnityAction<string>
//
// ★ 改完必须执行菜单：XLua/Generate Code（重新生成 Assets/XLua/Gen）
// =============================================================================
using System;
using System.Collections.Generic;
using XLua;

public static class XLuaProjectConfig
{
    // Lua-only UI access must survive IL2CPP managed stripping.
    [ReflectionUse]
    public static List<Type> UIReflectionUse = new List<Type>()
    {
        typeof(UnityEngine.Application),
        typeof(UnityEngine.PlayerPrefs),
        typeof(UnityEngine.Input),
        typeof(UnityEngine.Screen),
        typeof(UnityEngine.Camera),
        typeof(UnityEngine.Font),
        typeof(UnityEngine.GUIUtility),
        typeof(UnityEngine.Rect),
        typeof(UnityEngine.RectTransformUtility),
        typeof(UnityEngine.CanvasGroup),
        typeof(UnityEngine.Animator),
        typeof(UnityEngine.SceneManagement.SceneManager),
        typeof(UnityEngine.AsyncOperation),
        typeof(UnityEngine.SceneManagement.Scene),
        typeof(System.IO.File),
        typeof(System.IO.Path),
        typeof(ModCardDrag),
        typeof(MyAssetBundles.AssetBundleManager),
        typeof(UnityEngine.Canvas),
        typeof(UnityEngine.RectTransform),
        typeof(UnityEngine.UI.CanvasScaler),
        typeof(UnityEngine.UI.GraphicRaycaster),
        typeof(UnityEngine.EventSystems.EventSystem),
        typeof(UnityEngine.EventSystems.StandaloneInputModule),
        typeof(UnityEngine.UI.Graphic),
        typeof(UnityEngine.UI.Selectable),
        typeof(UnityEngine.UI.Button),
        typeof(UnityEngine.UI.Image),
        typeof(UnityEngine.UI.RawImage),
        typeof(UnityEngine.UI.Text),
        typeof(UnityEngine.UI.Toggle),
        typeof(UnityEngine.UI.Slider),
        typeof(UnityEngine.UI.ScrollRect),
        typeof(UnityEngine.UI.Scrollbar),
        typeof(UnityEngine.UI.InputField),
        typeof(UnityEngine.UI.LayoutRebuilder),
        typeof(UnityEngine.UI.Dropdown),
        typeof(UnityEngine.UI.GridLayoutGroup),
        typeof(UnityEngine.UI.Shadow),
        typeof(TMPro.TMP_InputField),
        typeof(TMPro.TMP_Text),
        typeof(TMPro.TextMeshProUGUI),
        typeof(TMPro.TMP_FontAsset),
        typeof(TMPro.TMP_Settings),
        // Preserve event return types and their inherited add/remove methods.
        typeof(UnityEngine.Events.UnityEvent),
        typeof(UnityEngine.Events.UnityEvent<bool>),
        typeof(UnityEngine.Events.UnityEvent<float>),
        typeof(UnityEngine.Events.UnityEvent<int>),
        typeof(UnityEngine.Events.UnityEvent<string>),
        typeof(UnityEngine.Events.UnityEvent<UnityEngine.Vector2>),
        typeof(UnityEngine.UI.Button.ButtonClickedEvent),
        typeof(UnityEngine.UI.Toggle.ToggleEvent),
        typeof(UnityEngine.UI.Slider.SliderEvent),
        typeof(UnityEngine.UI.ScrollRect.ScrollRectEvent),
        typeof(UnityEngine.UI.Scrollbar.ScrollEvent),
        typeof(UnityEngine.UI.Dropdown.DropdownEvent),
        typeof(UnityEngine.UI.InputField.OnChangeEvent),
        typeof(UnityEngine.UI.InputField.SubmitEvent),
        typeof(TMPro.TMP_InputField.OnChangeEvent),
        typeof(TMPro.TMP_InputField.SubmitEvent),
    };

    [CSharpCallLua]
    public static List<Type> CSharpCallLua = new List<Type>()
    {
        // ScrollRect.onValueChanged（UnityEvent<Vector2>）—— UIListView 虚拟滚动依赖
        typeof(UnityEngine.Events.UnityAction<UnityEngine.Vector2>),
        // Slider.onValueChanged（UnityEvent<float>）
        typeof(UnityEngine.Events.UnityAction<float>),
        // Toggle.onValueChanged（UnityEvent<bool>）
        typeof(UnityEngine.Events.UnityAction<bool>),
        // InputField.onValueChanged / onEndEdit（UnityEvent<string>）
        typeof(UnityEngine.Events.UnityAction<string>),
    };

    // -------------------------------------------------------------------------
    // LuaCallCSharp：Lua 需要高频/稳定访问的 C# 类型（生成静态包装，避免反射开销）
    // -------------------------------------------------------------------------
    [LuaCallCSharp]
    public static List<Type> LuaCallCSharp = new List<Type>()
    {
        // UI 资源从 AssetBundle 加载的桥（非泛型包装）
        // 使用方：Game/UI/Provider/AssetBundleProvider.lua
        typeof(UIAssetBundleHelper),
    };
}
