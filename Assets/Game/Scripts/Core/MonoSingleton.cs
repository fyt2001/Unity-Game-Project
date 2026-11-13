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
                            // 2. 自动创建。注意：不要在此把 go 挂到 Boot 下，
                            //    否则 Awake 里的 DontDestroyOnLoad(go) 作用在“非根节点”上会失效
                            //    （Unity 警告：DontDestroyOnLoad only works for root GameObjects），
                            //    单例将随场景卸载被销毁，导致 XLuaManager 的 LuaEnv 丢失，
                            //    进而 Trigger 登录后切到主界面又被弹回登录页。
                            GameObject go = new GameObject(typeof(T).Name);
                            _instance = go.AddComponent<T>();
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
        }
        else if (_instance != this)
        {
            // 防止场景中存在多个实例
            Destroy(gameObject);
            return;
        }

        // 关键修复：先以“根节点”身份标记 DontDestroyOnLoad，确保跨场景存活；
        // 之后再挂到 Boot 下做组织（此时已标记持久化，不会再触发“非根节点”警告）。
        DontDestroyOnLoad(gameObject);

        GameObject parent = GameObject.Find("Boot");
        if (parent == null)
        {
            parent = new GameObject("Boot");
            DontDestroyOnLoad(parent);
        }
        if (gameObject.transform.parent != parent.transform)
        {
            transform.SetParent(parent.transform);
        }

        Init();
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
