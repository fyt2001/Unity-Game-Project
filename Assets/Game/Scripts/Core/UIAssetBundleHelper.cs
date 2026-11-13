// =============================================================================
// UIAssetBundleHelper.cs - Lua 侧访问 AssetBundle 的非泛型桥
// =============================================================================
// 存在原因：
//   AssetBundleLoadAssetOperation.GetAsset<T>() 是泛型方法，且 T 被约束为 UnityEngine.Object。
//   XLua 无法从 Lua 直接调用「未登记泛型实参」的泛型方法，因此这里用一层非泛型的静态包装
//   把 API 暴露给 Lua，避免在 Lua 侧写 xlua.get_generic_method 这种脆弱写法。
//
// 使用方：
//   Assets/Game/LuaScripts/Game/UI/Provider/AssetBundleProvider.lua
//
// 注意：
//   本类需登记进 Assets/Editor/XLuaProjectConfig.cs 的 [LuaCallCSharp] 列表，
//   并执行菜单 XLua/Generate Code，才会有生成包装（否则退化为反射，性能差且行为不稳）。
// =============================================================================

using UnityEngine;
using MyAssetBundles;

public static class UIAssetBundleHelper
{
    /// <summary>
    /// 发起一次「UI prefab」的异步加载。
    /// 编辑器 Simulation 模式下同步走 AssetDatabase；真机走 AssetBundle 加载。
    /// </summary>
    /// <returns>加载操作对象；返回 null 表示发起失败（资源名或 bundle 名不对）。</returns>
    public static AssetBundleLoadAssetOperation LoadPrefabAsync(string bundleName, string assetName)
    {
        if (string.IsNullOrEmpty(bundleName) || string.IsNullOrEmpty(assetName))
            return null;
        return AssetBundleManager.LoadAssetAsync(bundleName, assetName, typeof(GameObject));
    }

    /// <summary>加载是否已完成。op 为 null 时返回 true（调用方随后会拿到 null 资源）。</summary>
    public static bool IsDone(AssetBundleLoadAssetOperation op)
    {
        return op == null || op.IsDone();
    }

    /// <summary>取加载到的 prefab。未完成或失败时返回 null。</summary>
    public static GameObject GetPrefab(AssetBundleLoadAssetOperation op)
    {
        return op == null ? null : op.GetAsset<GameObject>();
    }
}
