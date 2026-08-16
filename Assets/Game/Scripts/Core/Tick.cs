// =============================================================================
// Tick.cs - 全局Tick驱动系统（腾讯级生产标准）
// =============================================================================
// 来源: ShaoNvClient_H02 GameLaunch.Tick
// 说明: 统一管理 Update/LateUpdate/FixedUpdate 回调，支持优先级排序
// =============================================================================

using System;
using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// 全局 Tick 驱动系统。
/// 集中管理所有帧更新回调，支持优先级排序和动态注册/注销。
/// 在 GameLaunch 的 Update/LateUpdate/FixedUpdate 中调用对应方法。
/// </summary>
public static class Tick
{
    private class TickItem
    {
        public Action<float> Callback;
        public int Priority; // 越小越先执行
        public int Id;
    }

    private static readonly List<TickItem> _updateItems = new List<TickItem>();
    private static readonly List<TickItem> _lateUpdateItems = new List<TickItem>();
    private static readonly List<TickItem> _fixedUpdateItems = new List<TickItem>();
    private static int _nextId = 0;
    private static bool _dirty = false;

    /// <summary>
    /// 注册 Update 回调
    /// </summary>
    /// <returns>回调ID，用于注销</returns>
    public static int RegisterUpdate(Action<float> callback, int priority = 0)
    {
        var item = new TickItem { Callback = callback, Priority = priority, Id = ++_nextId };
        _updateItems.Add(item);
        _dirty = true;
        return item.Id;
    }

    /// <summary>
    /// 注册 LateUpdate 回调
    /// </summary>
    public static int RegisterLateUpdate(Action<float> callback, int priority = 0)
    {
        var item = new TickItem { Callback = callback, Priority = priority, Id = ++_nextId };
        _lateUpdateItems.Add(item);
        _dirty = true;
        return item.Id;
    }

    /// <summary>
    /// 注册 FixedUpdate 回调
    /// </summary>
    public static int RegisterFixedUpdate(Action<float> callback, int priority = 0)
    {
        var item = new TickItem { Callback = callback, Priority = priority, Id = ++_nextId };
        _fixedUpdateItems.Add(item);
        _dirty = true;
        return item.Id;
    }

    /// <summary>
    /// 注销回调
    /// </summary>
    public static void Unregister(int id)
    {
        RemoveById(_updateItems, id);
        RemoveById(_lateUpdateItems, id);
        RemoveById(_fixedUpdateItems, id);
    }

    private static void RemoveById(List<TickItem> list, int id)
    {
        for (int i = list.Count - 1; i >= 0; i--)
        {
            if (list[i].Id == id)
            {
                list.RemoveAt(i);
                break;
            }
        }
    }

    private static void SortIfDirty(List<TickItem> list)
    {
        if (_dirty)
        {
            list.Sort((a, b) => a.Priority.CompareTo(b.Priority));
        }
    }

    /// <summary>
    /// 驱动 Update（由 GameLaunch.Update 调用）
    /// </summary>
    public static void OnUpdate()
    {
        SortIfDirty(_updateItems);
        _dirty = false;

        float dt = Time.deltaTime;
        for (int i = 0; i < _updateItems.Count; i++)
        {
            try
            {
                _updateItems[i].Callback?.Invoke(dt);
            }
            catch (Exception e)
            {
                DebugLogger.Exception(e);
            }
        }
    }

    /// <summary>
    /// 驱动 LateUpdate（由 GameLaunch.LateUpdate 调用）
    /// </summary>
    public static void OnLateUpdate()
    {
        float dt = Time.deltaTime;
        for (int i = 0; i < _lateUpdateItems.Count; i++)
        {
            try
            {
                _lateUpdateItems[i].Callback?.Invoke(dt);
            }
            catch (Exception e)
            {
                DebugLogger.Exception(e);
            }
        }
    }

    /// <summary>
    /// 驱动 FixedUpdate（由 GameLaunch.FixedUpdate 调用）
    /// </summary>
    public static void OnFixedUpdate()
    {
        float dt = Time.fixedDeltaTime;
        for (int i = 0; i < _fixedUpdateItems.Count; i++)
        {
            try
            {
                _fixedUpdateItems[i].Callback?.Invoke(dt);
            }
            catch (Exception e)
            {
                DebugLogger.Exception(e);
            }
        }
    }

    /// <summary>
    /// 清理所有回调
    /// </summary>
    public static void Clear()
    {
        _updateItems.Clear();
        _lateUpdateItems.Clear();
        _fixedUpdateItems.Clear();
    }
}
