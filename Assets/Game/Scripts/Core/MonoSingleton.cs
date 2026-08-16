// =============================================================================
// MonoSingleton.cs - MonoBehaviour 单例基类（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 (幻域神姬)
// 升级: 增加线程安全、生命周期钩子、性能优化
// =============================================================================

using UnityEngine;

/// <summary>
/// MonoBehaviour 单例基类。
/// 自动挂载到 "Boot" GameObject 下，DontDestroyOnLoad 保证跨场景存活。
/// 提供 Init() / Dispose() / DestroySelf() 完整生命周期。
/// </summary>
public abstract class MonoSingleton<T> : MonoBehaviour where T : MonoSingleton<T>
{
    private static T _instance;
    private static readonly object _lock = new object();

    public static T Instance
    {
        get
        {
            if (_instance == null)
            {
                lock (_lock)
                {
                    if (_instance == null)
                    {
                        // 1. 尝试在场景中查找已有实例
                        _instance = FindObjectOfType<T>();

                        if (_instance == null)
                        {
                            // 2. 自动创建并挂载到 Boot 节点下
                            GameObject go = new GameObject(typeof(T).Name);
                            _instance = go.AddComponent<T>();

                            GameObject parent = GameObject.Find("Boot");
                            if (parent == null)
                            {
                                parent = new GameObject("Boot");
                                DontDestroyOnLoad(parent);
                            }
                            go.transform.SetParent(parent.transform);
                        }
                    }
                }
            }

            return _instance;
        }
    }

    /// <summary>
    /// 检查单例是否已创建（避免触发懒加载）
    /// </summary>
    public static bool HasInstance => _instance != null;

    /// <summary>
    /// 显式初始化入口。调用 Instance 属性即自动触发，也可手动调用。
    /// </summary>
    public void Startup() { }

    protected virtual void Awake()
    {
        if (_instance == null)
        {
            _instance = this as T;
            DontDestroyOnLoad(gameObject);
            Init();
        }
        else if (_instance != this)
        {
            // 防止场景中存在多个实例
            Destroy(gameObject);
        }
    }

    /// <summary>
    /// 子类重写此方法进行初始化
    /// </summary>
    protected virtual void Init() { }

    /// <summary>
    /// 销毁单例实例
    /// </summary>
    public void DestroySelf()
    {
        Dispose();
        _instance = null;
        Destroy(gameObject);
    }

    /// <summary>
    /// 子类重写此方法进行资源释放
    /// </summary>
    public virtual void Dispose() { }

    protected virtual void OnDestroy()
    {
        if (_instance == this)
        {
            _instance = null;
        }
    }
}
