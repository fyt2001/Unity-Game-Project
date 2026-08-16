// =============================================================================
// GameObjectPool.cs - GameObject对象池（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 AssetFactory（提炼核心池化逻辑）
// 升级: 独立通用池、支持预热、容量限制、自动回收
// =============================================================================

using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// 通用 GameObject 对象池。
/// 支持预热（Preload）、最大容量限制、自动回收检测。
/// 
/// 用法:
///   GameObjectPool pool = new GameObjectPool(prefab, 10);
///   GameObject obj = pool.Get();
///   pool.Release(obj);
/// </summary>
public class GameObjectPool
{
    private readonly GameObject _prefab;
    private readonly Transform _parent;
    private readonly Stack<GameObject> _poolStack;
    private readonly int _maxCapacity;
    private readonly int _preloadCount;

    /// <summary>
    /// 当前池中可用数量
    /// </summary>
    public int AvailableCount => _poolStack.Count;

    /// <summary>
    /// 预制体
    /// </summary>
    public GameObject Prefab => _prefab;

    /// <param name="prefab">预制体</param>
    /// <param name="preloadCount">预热数量</param>
    /// <param name="maxCapacity">最大容量（0=无限制）</param>
    /// <param name="parent">池父节点（null=自动创建）</param>
    public GameObjectPool(GameObject prefab, int preloadCount = 5, int maxCapacity = 100, Transform parent = null)
    {
        _prefab = prefab;
        _preloadCount = preloadCount;
        _maxCapacity = maxCapacity;

        // 创建池根节点
        if (parent == null)
        {
            GameObject poolRoot = new GameObject($"Pool_{prefab.name}");
            poolRoot.SetActive(false);
            Object.DontDestroyOnLoad(poolRoot);
            _parent = poolRoot.transform;
        }
        else
        {
            _parent = parent;
        }

        _poolStack = new Stack<GameObject>(maxCapacity > 0 ? maxCapacity : preloadCount);
        Preload();
    }

    /// <summary>
    /// 预热对象
    /// </summary>
    private void Preload()
    {
        for (int i = 0; i < _preloadCount; i++)
        {
            GameObject obj = CreateInstance();
            obj.SetActive(false);
            obj.transform.SetParent(_parent);
            _poolStack.Push(obj);
        }
    }

    private GameObject CreateInstance()
    {
        return Object.Instantiate(_prefab);
    }

    /// <summary>
    /// 从池中获取对象
    /// </summary>
    public GameObject Get()
    {
        GameObject obj;
        if (_poolStack.Count > 0)
        {
            obj = _poolStack.Pop();
            // 防止对象被意外销毁
            if (obj == null)
            {
                obj = CreateInstance();
            }
        }
        else
        {
            obj = CreateInstance();
        }

        obj.SetActive(true);
        obj.transform.SetParent(null);
        return obj;
    }

    /// <summary>
    /// 从池中获取对象并设置父节点
    /// </summary>
    public GameObject Get(Transform parent, bool resetTransform = true)
    {
        GameObject obj = Get();
        obj.transform.SetParent(parent);
        if (resetTransform)
        {
            obj.transform.ResetLocal();
        }
        return obj;
    }

    /// <summary>
    /// 回收对象到池中
    /// </summary>
    public void Release(GameObject obj)
    {
        if (obj == null) return;

        // 检查容量限制
        if (_maxCapacity > 0 && _poolStack.Count >= _maxCapacity)
        {
            Object.Destroy(obj);
            return;
        }

        obj.SetActive(false);
        obj.transform.SetParent(_parent);
        _poolStack.Push(obj);
    }

    /// <summary>
    /// 清空池
    /// </summary>
    public void Clear()
    {
        while (_poolStack.Count > 0)
        {
            GameObject obj = _poolStack.Pop();
            if (obj != null)
            {
                Object.Destroy(obj);
            }
        }
        _poolStack.Clear();
    }

    /// <summary>
    /// 销毁池
    /// </summary>
    public void Destroy()
    {
        Clear();
        if (_parent != null)
        {
            Object.Destroy(_parent.gameObject);
        }
    }
}

/// <summary>
/// 对象池管理器（全局单例）。
/// 统一管理多个 GameObjectPool 实例。
/// </summary>
public class PoolManager : SingletonBehaviour<PoolManager>
{
    private readonly Dictionary<string, GameObjectPool> _pools = new Dictionary<string, GameObjectPool>();

    /// <summary>
    /// 创建或获取对象池
    /// </summary>
    public GameObjectPool GetOrCreatePool(string key, GameObject prefab, int preloadCount = 5, int maxCapacity = 100)
    {
        GameObjectPool pool;
        if (!_pools.TryGetValue(key, out pool))
        {
            pool = new GameObjectPool(prefab, preloadCount, maxCapacity, transform);
            _pools[key] = pool;
        }
        return pool;
    }

    /// <summary>
    /// 获取已有对象池
    /// </summary>
    public GameObjectPool GetPool(string key)
    {
        _pools.TryGetValue(key, out GameObjectPool pool);
        return pool;
    }

    /// <summary>
    /// 快速获取对象
    /// </summary>
    public GameObject Get(string key, GameObject prefab, int preloadCount = 5)
    {
        var pool = GetOrCreatePool(key, prefab, preloadCount);
        return pool.Get();
    }

    /// <summary>
    /// 快速回收对象
    /// </summary>
    public void Release(string key, GameObject obj)
    {
        var pool = GetPool(key);
        pool?.Release(obj);
    }

    /// <summary>
    /// 销毁指定池
    /// </summary>
    public void DestroyPool(string key)
    {
        if (_pools.TryGetValue(key, out GameObjectPool pool))
        {
            pool.Destroy();
            _pools.Remove(key);
        }
    }

    /// <summary>
    /// 销毁所有池
    /// </summary>
    public void ClearAll()
    {
        foreach (var pool in _pools.Values)
        {
            pool.Destroy();
        }
        _pools.Clear();
    }

    protected override void OnDestroy()
    {
        ClearAll();
        base.OnDestroy();
    }
}
