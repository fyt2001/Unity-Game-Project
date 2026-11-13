// =============================================================================
// Interactable.cs
// =============================================================================
// 可交互物体标记组件。挂在场景里任何「能被鼠标点击触达」的对象上：
// 商人、传送门、宝箱、任务 NPC、开关 ...
//
// 职责单一：只描述「它可不可以被触发、怎么触发、触发什么」，
//           不做任何输入检测（检测统一交给 InteractionController）。
//
// 触发方式：
//   1. 鼠标左键点击（allowClick）
//   2. 玩家靠近自动触发（allowProximity）—— 用于「走进洞口即传送」这类表现
//
// 用法：
//   在 Inspector 里把要做的事情塞进 onInteract（UnityEvent），
//   或用 C# 订阅 OnInteracted 事件。
// =============================================================================

using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

[AddComponentMenu("Game/Interactable")]
public class Interactable : MonoBehaviour
{
    [Header("Identity")]
    [Tooltip("交互名称（悬停提示 / UI 显示用）")]
    public string interactName = "";

    [Header("Trigger")]
    [Tooltip("允许鼠标左键点击触发")]
    public bool allowClick = true;

    [Tooltip("允许玩家靠近时自动触发（如走进洞口传送）")]
    public bool allowProximity = false;

    [Tooltip("自动触发半径（世界单位）")]
    public float proximityRadius = 2.5f;

    [Tooltip("只触发一次（传送类推荐开启，避免回到场景后被重复判定）")]
    public bool triggerOnce = false;

    [Tooltip("是否可用。关掉后点击与靠近都不会触发")]
    public bool interactEnabled = true;

    [Header("Events")]
    public UnityEvent onInteract = new UnityEvent();

    /// <summary>C# 侧订阅入口（比 UnityEvent 更适合代码动态绑定）</summary>
    public event Action<Interactable> OnInteracted;

    /// <summary>场景中所有存活的 Interactable，避免 proximity 检测用 FindObjectsOfType 每帧扫场景</summary>
    public static readonly List<Interactable> All = new List<Interactable>();

    private bool _consumed;

    void OnEnable()
    {
        if (!All.Contains(this)) All.Add(this);
    }

    void OnDisable()
    {
        All.Remove(this);
    }

    /// <summary>触发交互。已触发过且勾选了 triggerOnce 的会被忽略。</summary>
    public void Interact()
    {
        if (!interactEnabled) return;
        if (triggerOnce && _consumed) return;

        if (triggerOnce) _consumed = true;

        onInteract?.Invoke();
        OnInteracted?.Invoke(this);
    }

    /// <summary>建筑辅助组件：给自身（及所有子物体）补上 MeshCollider，保证能被射线命中。</summary>
    public void EnsureColliders()
    {
        // MeshFilter 存在但没有 collider 的情况下补一个（CreatePrimitive 通常已有）
        foreach (var mf in GetComponentsInChildren<MeshFilter>(true))
        {
            if (mf.gameObject.GetComponent<Collider>() == null)
                mf.gameObject.AddComponent<MeshCollider>();
        }

        if (GetComponentInChildren<Collider>(true) == null)
        {
            // 没有任何网格可作为碰撞体时，退化成一个触发器球，保证点击体验不失效
            var col = gameObject.AddComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = Mathf.Max(0.5f, proximityRadius);
        }
    }

    void OnDrawGizmosSelected()
    {
        if (!allowProximity) return;
        Gizmos.color = new Color(0.27f, 0.95f, 0.63f, 0.5f);
        Gizmos.DrawWireSphere(transform.position, proximityRadius);
    }
}
