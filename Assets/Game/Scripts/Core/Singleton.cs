// =============================================================================
// Singleton.cs - 纯C#类单例基类（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 (幻域神姬)
// 升级: 线程安全双重检查锁、泛型约束优化
// =============================================================================

using System;

/// <summary>
/// 纯 C# 类单例基类（非 MonoBehaviour）。
/// 适用于不需要挂载到场景的管理器类（如 ChannelManager、ConfigManager）。
/// 使用双重检查锁保证线程安全。
/// </summary>
public abstract class Singleton<T> where T : class, new()
{
    private static T _instance;
    private static readonly object _lock = new object();

    public static T instance
    {
        get
        {
            if (_instance == null)
            {
                lock (_lock)
                {
                    if (_instance == null)
                    {
                        _instance = Activator.CreateInstance<T>();
                        (_instance as Singleton<T>)?.Init();
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

    /// <summary>
    /// 释放单例实例
    /// </summary>
    public static void Release()
    {
        lock (_lock)
        {
            if (_instance != null)
            {
                (_instance as Singleton<T>)?.Dispose();
                _instance = null;
            }
        }
    }

    /// <summary>
    /// 子类重写此方法进行初始化
    /// </summary>
    public virtual void Init() { }

    /// <summary>
    /// 子类重写此方法进行资源释放（必须实现）
    /// </summary>
    public abstract void Dispose();
}
