// =============================================================================
// UIComponentBinder.cs - Lua UI组件自动绑定系统（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine.GoldenLuaUIComponent
// 升级: 去除TMPro/Spine/Wwise等业务依赖，提取核心绑定逻辑，增加编辑器扩展点
//
// 设计思想: 约定优于配置（Convention over Configuration）
//   命名前缀约定:
//     m_xxx  - 普通UI组件绑定（如 m_BtnClose → 绑定Button）
//     mi_xxx - 额外绑定Image（如图片按钮，同时绑定Button+Image）
//     c_xxx  - Cell/Item组件绑定
//     ci_xxx - Cell/Item组件绑定（含Image）
//   特殊节点名:
//     SubRoot / CloseBtn / ReturnBtn / MaskBtn / CurrencyParent
// =============================================================================

using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using XLua;

/// <summary>
/// Lua UI 组件自动绑定器。
/// 挂载到 UI Prefab 根节点上，通过命名约定自动发现并绑定子节点UI组件。
/// </summary>
[Hotfix]
[DisallowMultipleComponent]
public class UIComponentBinder : MonoBehaviour
{
    /// <summary>
    /// 是否深度查找第一个 Button（用于 Item 组件自动绑定）
    /// </summary>
    public bool IsDeepFindFirstButton;

    /// <summary>
    /// 已绑定的组件列表
    /// </summary>
    [SerializeField]
    public UICompItem[] UICompList;

    /// <summary>
    /// Lua 实例引用
    /// </summary>
    public LuaTable LuaInstance;

    [Serializable]
    public class UICompItem
    {
        public string CompName;
        public Component Comp;
    }

    /// <summary>
    /// 组件类型 → Lua 缩写映射表
    /// </summary>
    private static readonly Dictionary<Type, string> TypeAbbrMap = new Dictionary<Type, string>
    {
        { typeof(Image),         "Img" },
        { typeof(RawImage),      "RawImg" },
        { typeof(Button),        "Btn" },
        { typeof(Text),          "Txt" },
        { typeof(ScrollRect),    "Srt" },
        { typeof(Slider),        "Sld" },
        { typeof(Scrollbar),     "Slb" },
        { typeof(InputField),    "Ipt" },
        { typeof(Dropdown),      "Dpd" },
        { typeof(Animation),     "Ani" },
        { typeof(Animator),      "Anr" },
        { typeof(Toggle),        "Tog" },
        { typeof(UIComponentBinder), "Cmp" },
    };

    /// <summary>
    /// 获取组件类型的 Lua 缩写
    /// </summary>
    public static string GetTypeAbbr(Component comp)
    {
        if (comp == null) return "Unknown";
        Type type = comp.GetType();
        foreach (var kv in TypeAbbrMap)
        {
            if (kv.Key.IsAssignableFrom(type))
                return kv.Value;
        }
        return type.Name;
    }

    /// <summary>
    /// 将绑定的组件注入 Lua 表
    /// </summary>
    public void LuaBindObject()
    {
        if (LuaInstance == null || UICompList == null) return;

        for (int i = 0; i < UICompList.Length; i++)
        {
            var item = UICompList[i];
            if (item.Comp != null)
            {
                LuaInstance.Set(item.CompName, item.Comp);
            }
        }
    }

    /// <summary>
    /// 执行自动绑定（递归遍历子节点）
    /// </summary>
    [ContextMenu("执行自动绑定")]
    public void Bind()
    {
        List<UICompItem> compItemList = new List<UICompItem>();

        // 绑定 SpriteAtlasBinder（如果项目中有此组件）
        // var spriteAtlasBinder = GetComponent<SpriteAtlasBinder>();
        // if (spriteAtlasBinder != null)
        // {
        //     AddUICompItem(compItemList, "atlas", spriteAtlasBinder);
        // }

        // 绑定自身 Button（用于 Item 组件）
        var selfButton = GetComponent<Button>();
        if (selfButton != null)
        {
            AddUICompItem(compItemList, "__ItemButton", selfButton);
        }
        else if (IsDeepFindFirstButton)
        {
            selfButton = GetComponentInChildren<Button>(true);
            if (selfButton != null)
            {
                AddUICompItem(compItemList, "__ItemButton", selfButton);
            }
        }

        // 递归遍历子节点
        for (int i = 0; i < transform.childCount; i++)
        {
            BuildBindings(compItemList, transform.GetChild(i));
        }

        UICompList = compItemList.ToArray();
    }

    private void BuildBindings(List<UICompItem> compItemList, Transform tran)
    {
        // 遇到嵌套的 UIComponentBinder，递归调用其 Bind 后停止
        var childBinder = tran.GetComponent<UIComponentBinder>();
        if (childBinder != null && childBinder != this)
        {
            childBinder.Bind();
            return;
        }

        // 特殊节点名处理
        ProcessSpecialNode(compItemList, tran);

        // 命名约定绑定
        bool isM = tran.name.StartsWith("m_");
        bool isMI = tran.name.StartsWith("mi_");
        bool isC = tran.name.StartsWith("c_");
        bool isCI = tran.name.StartsWith("ci_");

        if (isM || isMI || isC || isCI)
        {
            bool hasComponent = false;
            foreach (var typePair in TypeAbbrMap)
            {
                Type type = typePair.Key;

                // mi_ / ci_ 才绑定 Image
                if (type == typeof(Image) && !isMI && !isCI)
                {
                    var btn = tran.GetComponent<Button>();
                    if (btn != null) continue; // 有Button时跳过Image绑定
                }

                Component comp = tran.GetComponent(type);
                if (comp != null)
                {
                    AddUICompItem(compItemList, comp);

                    // Button 特殊处理：自动绑定子节点中的第一个 Text
                    if (comp is Button)
                    {
                        var childText = tran.GetComponentInChildren<Text>(true);
                        if (childText != null)
                        {
                            AddUICompItem(compItemList, comp.name + "_Button_Text", childText);
                        }

                        var childNormal = FindChildDeep(tran, "Normal");
                        if (childNormal != null)
                        {
                            AddUICompItem(compItemList, comp.name + "_Button_Normal", childNormal);
                        }

                        var childGray = FindChildDeep(tran, "Gray");
                        var grayImg = childGray?.GetComponent<Image>();
                        if (grayImg != null)
                        {
                            AddUICompItem(compItemList, comp.name + "_Button_Gray", grayImg);
                        }
                    }

                    hasComponent = true;
                }
            }

            // 无组件时绑定自身 Transform
            if (!hasComponent)
            {
                AddUICompItem(compItemList, tran.name + "_Transform", tran);
            }
        }

        // 继续遍历子节点
        for (int i = 0; i < tran.childCount; i++)
        {
            BuildBindings(compItemList, tran.GetChild(i));
        }
    }

    private void ProcessSpecialNode(List<UICompItem> compItemList, Transform tran)
    {
        switch (tran.name)
        {
            case "SubRoot":
                AddUICompItem(compItemList, "subRootTrans", tran);
                break;

            case "CurrencyParent":
                AddUICompItem(compItemList, tran.name, tran);
                break;

            case "CloseBtn":
            case "ReturnBtn":
            case "MaskBtn":
                var btn = tran.GetComponent<Button>();
                if (btn != null)
                {
                    AddUICompItem(compItemList, tran.name + "_" + btn.GetType().Name, btn);
                }
                break;
        }
    }

    private Transform FindChildDeep(Transform trans, string name)
    {
        Transform result = trans.Find(name);
        if (result != null) return result;

        for (int i = 0; i < trans.childCount; i++)
        {
            result = FindChildDeep(trans.GetChild(i), name);
            if (result != null) return result;
        }
        return null;
    }

    private void AddUICompItem(List<UICompItem> list, string compName, Component comp)
    {
        var existing = list.Find(p => p.CompName == compName);
        if (existing != null)
        {
            Debug.LogWarning($"UIComponentBinder: 重名绑定 '{compName}'，已覆盖", comp.gameObject);
            existing.Comp = comp;
        }
        else
        {
            list.Add(new UICompItem { CompName = compName, Comp = comp });
        }
    }

    private void AddUICompItem(List<UICompItem> list, Component comp)
    {
        string abbr = GetTypeAbbr(comp);
        string compName = $"{comp.name}_{abbr}";
        AddUICompItem(list, compName, comp);
    }
}

/// <summary>
/// UI Item 组件绑定器（语义标记，继承 UIComponentBinder）
/// </summary>
[DisallowMultipleComponent]
public class UIItemComponentBinder : UIComponentBinder
{
}

/// <summary>
/// UI 页面根节点标记（Marker Pattern）
/// </summary>
[DisallowMultipleComponent]
public class PageRoot : MonoBehaviour
{
}
