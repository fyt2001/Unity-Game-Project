using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.U2D;
using MyAssetBundles;

/// <summary>
/// 把 AssetBundle 中的 SpriteAtlas 绑定到运行时 sprite。
///
/// 关键背景：SpriteAtlas 一旦被打进 AssetBundle（我们这里是 137 个 `atalas/<name>.asset`），
/// Unity 不会自动把图集纹理绑定到引用了它的 sprite，必须在启动时注册
/// <see cref="SpriteAtlasManager.atlasRequested"/> 回调，从对应 AB 取出 SpriteAtlas 并回传。
/// 缺少这一步，UI 的 Image 实际取不到图集纹理（回退到散图甚至丢失），图集等于没用上。
/// H02 在 ResourcesManager 里正是这么做的，这里按同样模式实现。
///
/// 图集包命名规则（与 BuildAssetBundles 一致）：`atalas/<SpriteAtlas名小写>.asset`，
/// 例如 UIAtalas/Battle.spriteatlas -> atalas/battle.asset。
/// </summary>
public sealed class AtlasBinder : MonoBehaviour
{
    private static AtlasBinder _instance;

    // 已加载的图集缓存：atlas 名(小写) -> SpriteAtlas
    private static readonly Dictionary<string, SpriteAtlas> Cache =
        new Dictionary<string, SpriteAtlas>(StringComparer.OrdinalIgnoreCase);

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
    private static void AutoStart()
    {
        if (_instance != null) return;
        var go = new GameObject("[AtlasBinder]");
        UnityEngine.Object.DontDestroyOnLoad(go);
        _instance = go.AddComponent<AtlasBinder>();
    }

    private void Awake()
    {
        SpriteAtlasManager.atlasRequested += RequestAtlas;
    }

    private void OnDestroy()
    {
        SpriteAtlasManager.atlasRequested -= RequestAtlas;
    }

    private void RequestAtlas(string tag, Action<SpriteAtlas> callback)
    {
        StartCoroutine(LoadAtlas(tag, callback));
    }

    private IEnumerator LoadAtlas(string tag, Action<SpriteAtlas> callback)
    {
        if (string.IsNullOrEmpty(tag))
        {
            callback(null);
            yield break;
        }

        string key = tag.ToLowerInvariant();
        if (Cache.TryGetValue(key, out var cached) && cached != null)
        {
            callback(cached);
            yield break;
        }

        // 图集包名固定为 atalas/<name>.asset（见 BuildAssetBundles 的 atalas 标签）
        string bundleName = "atalas/" + key + ".asset";

        var op = AssetBundleManager.LoadAssetAsync(bundleName, tag, typeof(SpriteAtlas));
        if (op == null)
        {
            callback(null);
            yield break;
        }

        yield return op;

        SpriteAtlas atlas = op.IsDone() ? op.GetAsset<SpriteAtlas>() : null;
        if (atlas != null) Cache[key] = atlas;
        callback(atlas);
    }
}
