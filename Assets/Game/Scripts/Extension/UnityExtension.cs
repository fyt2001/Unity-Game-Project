// =============================================================================
// UnityExtension.cs - Unity扩展方法库（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GoldenEngine
// 升级: 去除TMPro/GoldenButton等业务依赖，增加更多便捷方法
// =============================================================================

using System.Text;
using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// Unity 相关扩展方法集合。
/// 提供 GameObject/Transform/RectTransform/Image/Graphic 的流畅 API。
/// </summary>
[XLua.LuaCallCSharp]
public static class UnityExtension
{
    #region GameObject

    /// <summary>
    /// GetComponent 失败则自动 AddComponent
    /// </summary>
    public static T SafeGetComponent<T>(this GameObject go) where T : Component
    {
        if (go == null)
        {
            Debug.LogError("[UnityExtension] SafeGetComponent: GameObject is null");
            return null;
        }

        T component = go.GetComponent<T>();
        if (component == null)
        {
            component = go.AddComponent<T>();
        }
        return component;
    }

    /// <summary>
    /// 添加子节点并自动同步 layer、重置 Transform
    /// </summary>
    public static void AddChild(this GameObject parent, GameObject child)
    {
        if (parent != null && child != null)
        {
            child.transform.SetParent(parent.transform);
            child.layer = parent.layer;
            child.transform.ResetLocal();
        }
    }

    /// <summary>
    /// 设置父节点
    /// </summary>
    public static void SetParent(this GameObject child, GameObject parent)
    {
        parent?.AddChild(child);
    }

    /// <summary>
    /// 重置 RectTransform
    /// </summary>
    public static void ResetRectTransform(this GameObject go)
    {
        if (go != null)
        {
            go.GetComponent<RectTransform>()?.ResetRect();
        }
    }

    /// <summary>
    /// 根据名称查找子节点（广度优先）
    /// </summary>
    public static Transform GetChildByName(this GameObject gameObject, string name)
    {
        return gameObject != null ? gameObject.transform.GetChildByName(name) : null;
    }

    /// <summary>
    /// 获取完整层级路径
    /// </summary>
    public static string GetHierarchyPath(this GameObject go)
    {
        if (go == null) return "";

        string path = "/" + go.name;
        while (go.transform.parent != null)
        {
            go = go.transform.parent.gameObject;
            path = "/" + go.name + path;
        }
        return path;
    }

    #endregion

    #region Transform

    public static Transform SetX(this Transform transform, float x, bool isLocal = true)
    {
        if (transform == null) return null;
        if (isLocal)
            transform.localPosition = new Vector3(x, transform.localPosition.y, transform.localPosition.z);
        else
            transform.position = new Vector3(x, transform.position.y, transform.position.z);
        return transform;
    }

    public static Transform SetY(this Transform transform, float y, bool isLocal = true)
    {
        if (transform == null) return null;
        if (isLocal)
            transform.localPosition = new Vector3(transform.localPosition.x, y, transform.localPosition.z);
        else
            transform.position = new Vector3(transform.position.x, y, transform.position.z);
        return transform;
    }

    public static Transform SetZ(this Transform transform, float z, bool isLocal = true)
    {
        if (transform == null) return null;
        if (isLocal)
            transform.localPosition = new Vector3(transform.localPosition.x, transform.localPosition.y, z);
        else
            transform.position = new Vector3(transform.position.x, transform.position.y, z);
        return transform;
    }

    /// <summary>
    /// 重置 Transform（世界坐标）
    /// </summary>
    public static void Reset(this Transform transform)
    {
        if (transform != null)
        {
            transform.position = Vector3.zero;
            transform.rotation = Quaternion.identity;
            transform.localScale = Vector3.one;
        }
    }

    /// <summary>
    /// 重置 Transform（本地坐标）
    /// </summary>
    public static void ResetLocal(this Transform transform)
    {
        if (transform != null)
        {
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
            transform.localScale = Vector3.one;
        }
    }

    /// <summary>
    /// 根据名称查找子节点（广度优先）
    /// </summary>
    public static Transform GetChildByName(this Transform tr, string name)
    {
        if (tr == null || string.IsNullOrEmpty(name)) return null;

        foreach (Transform child in tr)
        {
            if (child.name == name)
                return child;
        }

        foreach (Transform child in tr)
        {
            Transform c = GetChildByName(child, name);
            if (c != null)
                return c;
        }

        return null;
    }

    /// <summary>
    /// 获取完整 Transform 路径
    /// </summary>
    public static string GetPath(this Transform obj)
    {
        var sb = new StringBuilder();
        while (obj != null)
        {
            sb.Insert(0, obj.name + "/");
            obj = obj.parent;
        }
        return sb.ToString();
    }

    #endregion

    #region RectTransform

    /// <summary>
    /// 重置 RectTransform
    /// </summary>
    public static void ResetRect(this RectTransform transform)
    {
        if (transform != null)
        {
            transform.anchoredPosition3D = Vector3.zero;
            transform.sizeDelta = Vector2.zero;
            transform.localScale = Vector3.one;
        }
    }

    public static void SetLocalPosition(this RectTransform transform, float x, float y, float z)
    {
        if (transform != null)
            transform.localPosition = new Vector3(x, y, z);
    }

    public static void SetLocalPositionX(this RectTransform transform, float x)
    {
        if (transform != null)
        {
            Vector3 v = transform.localPosition;
            v.x = x;
            transform.localPosition = v;
        }
    }

    public static void SetLocalPositionY(this RectTransform transform, float y)
    {
        if (transform != null)
        {
            Vector3 v = transform.localPosition;
            v.y = y;
            transform.localPosition = v;
        }
    }

    public static void SetAnchorPosition(this RectTransform transform, float x, float y, float z)
    {
        if (transform != null)
            transform.anchoredPosition = new Vector3(x, y, z);
    }

    public static void SetRotation(this RectTransform transform, float x, float y, float z, float w = 1)
    {
        if (transform != null)
            transform.rotation = new Quaternion(x, y, z, w);
    }

    public static Vector3 AppendLocalPosition(this RectTransform rectTransform, float x, float y)
    {
        return rectTransform.AppendLocalPosition(new Vector3(x, y));
    }

    public static Vector3 AppendLocalPosition(this RectTransform rectTransform, Vector3 vector3)
    {
        if (rectTransform == null) return Vector3.zero;
        var localPosition = rectTransform.localPosition;
        localPosition += vector3;
        rectTransform.localPosition = localPosition;
        return localPosition;
    }

    public static Vector2 RectangleContainsScreenPoint(this RectTransform rectTransform, Vector3 screenPoint, Camera camera)
    {
        RectTransformUtility.ScreenPointToLocalPointInRectangle(rectTransform, screenPoint, camera, out var localPosition);
        return localPosition;
    }

    public static Vector3[] GetWorldCornersEx(this RectTransform rectTransform)
    {
        Vector3[] array = new Vector3[4];
        rectTransform.GetWorldCorners(array);
        return array;
    }

    public static Vector3[] GetLocalCornersEx(this RectTransform rectTransform)
    {
        Vector3[] array = new Vector3[4];
        rectTransform.GetLocalCorners(array);
        return array;
    }

    #endregion

    #region UI Components

    /// <summary>
    /// 安全设置文字颜色
    /// </summary>
    public static void SetTextColor(this Graphic graphic, float r, float g, float b, float a)
    {
        if (graphic != null)
            graphic.color = new Color(r, g, b, a);
    }

    /// <summary>
    /// 设置 Image 透明度
    /// </summary>
    public static void SetAlpha(this Image img, float alpha)
    {
        if (img != null)
        {
            var color = img.color;
            img.color = new Color(color.r, color.g, color.b, alpha);
        }
    }

    /// <summary>
    /// 设置 Image 颜色
    /// </summary>
    public static void SetColor(this Image img, float r, float g, float b, float alpha)
    {
        if (img != null)
            img.color = new Color(r, g, b, alpha);
    }

    /// <summary>
    /// 便捷获取子节点组件
    /// </summary>
    public static Image GetChildImage(this Transform root, string childName)
    {
        return root.GetChildByName(childName)?.GetComponent<Image>();
    }

    public static Text GetChildText(this Transform root, string childName)
    {
        return root.GetChildByName(childName)?.GetComponent<Text>();
    }

    #endregion

    #region Utility

    /// <summary>
    /// 占位符字符串替换。格式: "hello #v1# world #v2#" 参数按序号对应
    /// </summary>
    public static string StringReplaceEx(string value, params object[] param)
    {
        if (param == null || param.Length == 0)
            return value;

        for (int i = 1; i < int.MaxValue; i++)
        {
            string key = $"#v{i}#";
            if (!value.Contains(key))
                return value;

            int j = i - 1;
            if (j >= param.Length)
                return value;
            value = value.Replace(key, param[j]?.ToString() ?? "null");
        }

        return value;
    }

    /// <summary>
    /// Unity Object 安全 null 检查（处理重载 == 的问题）
    /// </summary>
    public static bool IsNull(this Object obj)
    {
        return obj == null;
    }

    #endregion
}
