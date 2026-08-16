// =============================================================================
// SingletonBehaviour.cs - 轻量MonoBehaviour单例（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 (幻域神姬)
// 说明: 比 MonoSingleton 更轻量，不强制 Boot 节点，自动 DontDestroyOnLoad
// =============================================================================

using UnityEngine;

/// <summary>
/// 轻量 MonoBehaviour 单例基类。
/// 不强制挂载到 Boot 节点，自动 DontDestroyOnLoad。
/// 适用于需要独立 GameObject 的管理器（如 ResourcesManager）。
/// </summary>
public abstract class SingletonBehaviour<T> : MonoBehaviour where T : MonoBehaviour
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
                        _instance = FindObjectOfType<T>();

                        if (_instance == null)
                        {
                            GameObject obj = new GameObject(typeof(T).Name);
                            _instance = obj.AddComponent<T>();
                        }

                        if (_instance != null)
                        {
                            DontDestroyOnLoad(_instance.gameObject);
                        }
                    }
                }
            }

            return _instance;
        }
    }

    /// <summary>
    /// 检查单例是否已创建
    /// </summary>
    public static bool HasInstance => _instance != null;

    protected virtual void Awake()
    {
        if (_instance != null && _instance != this)
        {
            DestroyImmediate(gameObject);
            return;
        }

        _instance = this as T;
        DontDestroyOnLoad(gameObject);
    }

    protected virtual void OnDestroy()
    {
        if (_instance == this)
        {
            _instance = null;
        }
    }
}
